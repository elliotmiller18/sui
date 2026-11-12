#include "tools/SuiOptions.h"
//
// Created by Xuefeng Huang on 2020/1/31.
//

#include <solver/BestResponse.h>
#include "solver/PCfrSolver.h"
// Written for Sui by us: inspect training-state storage before allocating it.
#include <functional>
#include <cstdlib>
#include <sstream>
#include <unistd.h>
#include <fcntl.h>
#include <cstdio>

//#define DEBUG;

PCfrSolver::PCfrSolver(shared_ptr<GameTree> tree, vector<PrivateCards> range1, vector<PrivateCards> range2,
                     vector<int> initial_board, shared_ptr<Compairer> compairer, Deck deck, int iteration_number, bool debug,
                     int print_interval, string logfile, string trainer, Solver::MonteCarolAlg monteCarolAlg,int warmup,float accuracy,bool use_isomorphism,int num_threads) :Solver(tree){
    this->initial_board = initial_board;
    this->initial_board_long = Card::boardInts2long(initial_board);
    this->logfile = logfile;
    this->trainer = trainer;
    this->warmup = warmup;

    range1 = this->noDuplicateRange(range1,initial_board_long);
    range2 = this->noDuplicateRange(range2,initial_board_long);

    this->range1 = range1;
    this->range2 = range2;
    this->player_number = 2;
    this->ranges = vector<vector<PrivateCards>>(this->player_number);
    this->ranges[0] = range1;
    this->ranges[1] = range2;

    this->compairer = compairer;

    this->deck = deck;
    this->use_isomorphism = use_isomorphism;

    this->rrm = RiverRangeManager(compairer);
    this->rrm.initialize(initial_board_long);
    this->iteration_number = iteration_number;

    vector<vector<PrivateCards>> private_cards(this->player_number);
    private_cards[0] = range1;
    private_cards[1] = range2;
    pcm = PrivateCardsManager(private_cards,this->player_number,Card::boardInts2long(this->initial_board));
    this->debug = debug;
    this->print_interval = print_interval;
    this->monteCarolAlg = monteCarolAlg;
    this->accuracy = accuracy;
    if(num_threads == -1){
        num_threads = omp_get_num_procs();
    }
    cout << fmt::format("Using {} threads",num_threads) << endl;
    this->num_threads = num_threads;
    this->distributing_task = false;
    omp_set_num_threads(this->num_threads);
    // Written for Sui by us: each future board gets separate regret/average
    // arrays. Count that storage without materializing the arrays. No suit
    // isomorphism discount is assumed, so this is a conservative size estimate.
    const int starting_round = GameTreeNode::gameRound2int(this->tree->getRoot()->getRound());
    if(sui::options.slab&&sui::options.canonicalSlabs&&use_isomorphism){
        if(warmup>=0)throw runtime_error("Canonical slabs require warmup disabled");
        findGameSpecificIsomorphisms();
    }
    if(sui::options.slab)for(int p=0;p<2;++p)for(int gap=0;gap<=3-starting_round;++gap)dealLayouts[p][gap]=make_shared<DealLayout>(ranges[p],deck.getCards(),initial_board_long,gap,sui::options.blocked,(sui::options.canonicalSlabs&&use_isomorphism)?color_iso_offset:nullptr);
    const size_t undealt_cards = this->deck.getCards().size() - initial_board.size();
    json layoutStatistics=json::array();
    std::function<double(shared_ptr<GameTreeNode>)> storage = [&](shared_ptr<GameTreeNode> node) -> double {
        if(node->getType() == GameTreeNode::ACTION){
            auto action = (sui::options.dispatch ? std::static_pointer_cast<ActionNode>(node) : std::dynamic_pointer_cast<ActionNode>(node));
            const int gap = GameTreeNode::gameRound2int(node->getRound()) - starting_round;
            double boards = 1;
            for(int i = 0; i < gap; ++i) boards *= undealt_cards - i;
            const double hand_count = this->ranges[action->getPlayer()].size();
            double bytes = boards * (sizeof(DiscountedCfrTrainable) + sizeof(float) * hand_count * (2 * action->getActions().size()));
            // Written for Sui by us: include the preallocated board-slot vectors.
            const double slots = gap == 2 ? 2757 : (gap == 1 ? 53 : 1);
            bytes += slots * sizeof(shared_ptr<Trainable>);
            if(sui::options.slab){
                auto& layout=*dealLayouts[action->getPlayer()][gap];
                const size_t floatBytes=(sui::options.halfAverage?2:4)+(sui::options.halfRegret?2:4);
                bytes=layout.totalHands*action->getActions().size()*floatBytes+layout.rows*(sizeof(PackedTrainable)+1)+sizeof(PackedStore);
            }

            if(sui::options.phases)layoutStatistics.push_back({{"street_gap",gap},{"player",action->getPlayer()},{"hands",hand_count},{"actions",action->getActions().size()},{"public_states",sui::options.slab?double(dealLayouts[action->getPlayer()][gap]->rows):boards},{"state_bytes",bytes}});
            for(auto child: action->getChildrens()) bytes += storage(child);
            return bytes;
        }
        if(node->getType() == GameTreeNode::CHANCE)
            return storage((sui::options.dispatch ? std::static_pointer_cast<ChanceNode>(node) : std::dynamic_pointer_cast<ChanceNode>(node))->getChildren());
        return 0;
    };
    const double estimate_mb = storage(this->tree->getRoot()) / (1024 * 1024);
    cout << fmt::format("Sui estimated strategy storage: {:.1f} MiB", estimate_mb) << endl;
    if(sui::options.phases)cout<<"SUI_STATE_LAYOUT: "<<layoutStatistics.dump()<<endl;
    if(const char* limit = std::getenv("SUI_SOLVER_MEMORY_LIMIT_MB")){
        const double limit_mb = std::stod(limit);
        if(limit_mb > 0 && estimate_mb > limit_mb){
            // Written for Sui by us: exact estimate for whole-GiB UI retry sizing.
            cerr << fmt::format("SUI_MEMORY_REQUIRED_MB: {:.17g}", estimate_mb) << endl;
            const string message = fmt::format("SUI_MEMORY_LIMIT: Estimated strategy RAM {:.1f} GiB exceeds the {:.1f} GiB RAM budget. Reduce future-street sizes or raise depth.", estimate_mb / 1024, limit_mb / 1024);
            cerr << message << endl;
            throw runtime_error(message);
        }
    }
    setTrainable(this->tree->getRoot());
    this->root_round = this->tree->getRoot()->getRound();
    if(this->root_round == GameTreeNode::GameRound::PREFLOP){
        this->split_round = GameTreeNode::GameRound::FLOP;
    }else if(this->root_round == GameTreeNode::GameRound::FLOP){
        this->split_round = GameTreeNode::GameRound::TURN;
    }else if(this->root_round == GameTreeNode::GameRound::TURN){
        this->split_round = GameTreeNode::GameRound::RIVER;
    }else{
        // do not use multithread in river, really not necessary
        this->split_round = GameTreeNode::GameRound::PREFLOP;
    }
}

const vector<PrivateCards> &PCfrSolver::playerHands(int player) {
    if(player == 0){
        return range1;
    }else if (player == 1){
        return range2;
    }else{
        throw runtime_error("player not found");
    }
}

vector<vector<float>> PCfrSolver::getReachProbs() {
    vector<vector<float>> retval(this->player_number);
    for(int player = 0;player < this->player_number;player ++){
        vector<PrivateCards> player_cards = this->playerHands(player);
        vector<float> reach_prob(player_cards.size());
        for(int i = 0;i < player_cards.size();i ++){
            reach_prob[i] = player_cards[i].weight;
        }
        retval[player] = reach_prob;
    }
    return retval;
}

vector<PrivateCards>
PCfrSolver::noDuplicateRange(const vector<PrivateCards> &private_range, uint64_t board_long) {
    vector<PrivateCards> range_array;
    unordered_map<int,bool> rangekv;
    for(PrivateCards one_range:private_range){
        if(rangekv.find(one_range.hashCode()) != rangekv.end())
            throw runtime_error(fmt::format("duplicated key {}",one_range.toString()));
        rangekv[one_range.hashCode()] = true;
        uint64_t hand_long = Card::boardInts2long(one_range.get_hands());
        if(!Card::boardsHasIntercept(hand_long,board_long)){
            range_array.push_back(one_range);
        }
    }
    return range_array;

}

void PCfrSolver::setTrainable(shared_ptr<GameTreeNode> root) {
    if(root->getType() == GameTreeNode::ACTION){
        shared_ptr<ActionNode> action_node = std::dynamic_pointer_cast<ActionNode>(root);

        int player = action_node->getPlayer();

        if(this->trainer == "cfr_plus"){
            //vector<PrivateCards> player_privates = this->ranges[player];
            //action_node->setTrainable(make_shared<CfrPlusTrainable>(action_node,player_privates));
            throw runtime_error(fmt::format("trainer {} not supported",this->trainer));
        }else if(this->trainer == "discounted_cfr"){
            vector<PrivateCards>* player_privates = &this->ranges[player];
            //action_node->setTrainable(make_shared<DiscountedCfrTrainable>(action_node,player_privates));
            int num;
            GameTreeNode::GameRound gr = this->tree->getRoot()->getRound();
            int root_round = GameTreeNode::gameRound2int(gr);
            int current_round = GameTreeNode::gameRound2int(root->getRound());
            int gap = current_round - root_round;

            if(gap == 2) {
                num = this->deck.getCards().size() * this->deck.getCards().size() +
                          this->deck.getCards().size() + 1;
            }else if(gap == 1) {
                num = this->deck.getCards().size() + 1;
            }else if(gap == 0) {
                num =  1;
            }else{
                throw runtime_error("gap not understand");
            }
            if(sui::options.slab)action_node->setPacked(dealLayouts[player][gap],player_privates);
            else action_node->setTrainable(vector<shared_ptr<Trainable>>(num),player_privates);
        }else{
            throw runtime_error(fmt::format("trainer {} not found",this->trainer));
        }

        vector<shared_ptr<GameTreeNode>> childrens =  action_node->getChildrens();
        for(shared_ptr<GameTreeNode> one_child:childrens) setTrainable(one_child);
    }else if(root->getType() == GameTreeNode::CHANCE) {
        shared_ptr<ChanceNode> chance_node = std::dynamic_pointer_cast<ChanceNode>(root);
        shared_ptr<GameTreeNode> children = chance_node->getChildren();
        setTrainable(children);
    }
    else if(root->getType() == GameTreeNode::TERMINAL){

    }else if(root->getType() == GameTreeNode::SHOWDOWN){

    }
}

vector<int> PCfrSolver::getAllAbstractionDeal(int deal){
    vector<int> all_deal;
    int card_num = this->deck.getCards().size();
    if(deal == 0){
        all_deal.push_back(deal);
    } else if (deal > 0 && deal <= card_num){
        int origin_deal = int((deal - 1) / 4) * 4;
        for(int i = 0;i < 4;i ++){
            int one_card = origin_deal + i + 1;

            Card *first_card = const_cast<Card *>(&(this->deck.getCards()[origin_deal + i]));
            uint64_t first_long = Card::boardInt2long(
                    first_card->getCardInt());
            if (Card::boardsHasIntercept(first_long, this->initial_board_long))continue;
            all_deal.push_back(one_card);
        }
    } else{
        //cout << "______________________" << endl;
        int c_deal = deal - (1 + card_num);
        int first_deal = int((c_deal / card_num) / 4) * 4;
        int second_deal = int((c_deal % card_num) / 4) * 4;

        for(int i = 0;i < 4;i ++) {
            for(int j = 0;j < 4;j ++) {
                if(first_deal == second_deal && i == j) continue;

                Card *first_card = const_cast<Card *>(&(this->deck.getCards()[first_deal + i]));
                uint64_t first_long = Card::boardInt2long(
                        first_card->getCardInt());
                if (Card::boardsHasIntercept(first_long, this->initial_board_long))continue;

                Card *second_card = const_cast<Card *>(&(this->deck.getCards()[second_deal + j]));
                uint64_t second_long = Card::boardInt2long(
                        second_card->getCardInt());
                if (Card::boardsHasIntercept(second_long, this->initial_board_long))continue;

                int one_card = card_num * (first_deal + i) + (second_deal + j) + 1 + card_num;
                //cout << ";" << this->deck.getCards()[first_deal + i].toString() << "," << this->deck.getCards()[second_deal + j].toString();
                all_deal.push_back(one_card);
            }
        }
        //cout << endl;
    }
    return all_deal;
}

vector<float> PCfrSolver::cfr(int player, shared_ptr<GameTreeNode> node, const vector<float> &reach_probs, int iter,
                                    uint64_t current_board,int deal) {
    switch(node->getType()) {
        case GameTreeNode::ACTION: {
            shared_ptr<ActionNode> action_node = (sui::options.dispatch ? std::static_pointer_cast<ActionNode>(node) : std::dynamic_pointer_cast<ActionNode>(node));
            return actionUtility(player, action_node, reach_probs, iter, current_board,deal);
        }case GameTreeNode::SHOWDOWN: {
            shared_ptr<ShowdownNode> showdown_node = (sui::options.dispatch ? std::static_pointer_cast<ShowdownNode>(node) : std::dynamic_pointer_cast<ShowdownNode>(node));
            return showdownUtility(player, showdown_node, reach_probs, iter, current_board,deal);
        }case GameTreeNode::TERMINAL: {
            shared_ptr<TerminalNode> terminal_node = (sui::options.dispatch ? std::static_pointer_cast<TerminalNode>(node) : std::dynamic_pointer_cast<TerminalNode>(node));
            return terminalUtility(player, terminal_node, reach_probs, iter, current_board,deal);
        }case GameTreeNode::CHANCE: {
            shared_ptr<ChanceNode> chance_node = (sui::options.dispatch ? std::static_pointer_cast<ChanceNode>(node) : std::dynamic_pointer_cast<ChanceNode>(node));
            return chanceUtility(player, chance_node, reach_probs, iter, current_board,deal);
        }default:
            throw runtime_error("node type unknown");
    }
}

vector<float>
PCfrSolver::chanceUtility(int player, shared_ptr<ChanceNode> node, const vector<float> &reach_probs, int iter,
                         uint64_t current_board,int deal) {
    vector<Card>& cards = this->deck.getCards();
    //float[] cardWeights = getCardsWeights(player,reach_probs[1 - player],current_board);

    int card_num = node->getCards().size();
    if(card_num % 4 != 0) throw runtime_error("card num cannot round 4");
    // 可能的发牌情况,2代表每个人的holecard是两张
    int possible_deals = node->getCards().size() - Card::long2board(current_board).size() - 2;
    int oppo = 1 - player;

    //vector<float> chance_utility(reach_probs[player].size());
    vector<float> chance_utility = vector<float>(this->ranges[player].size());
    fill(chance_utility.begin(),chance_utility.end(),0);

    int random_deal = 0;
    if(this->monteCarolAlg==MonteCarolAlg::PUBLIC) {
        if (this->round_deal[GameTreeNode::gameRound2int(node->getRound())] == -1) {
            random_deal = random(1, possible_deals + 1 + 2);
            this->round_deal[GameTreeNode::gameRound2int(node->getRound())] = random_deal;
        } else {
            random_deal = this->round_deal[GameTreeNode::gameRound2int(node->getRound())];
        }
    }
    //vector<vector<vector<float>>> arr_new_reach_probs = vector<vector<vector<float>>>(node->getCards().size());

    vector<vector<float>> results(node->getCards().size());
    //fill(results.begin(),results.end(),nullptr);

    vector<float> multiplier;
    if(iter <= this->warmup){
        multiplier = vector<float>(card_num);
        fill(multiplier.begin(), multiplier.end(), 0);
        for (int card_base = 0; card_base < card_num / 4; card_base++) {
            int cardr = std::rand() % 4;
            int card_target = card_base * 4 + cardr;
            int multiplier_num = 0;
            for (int i = 0; i < 4; i++) {
                int i_card = card_base * 4 + i;
                if (i == cardr) {
                    Card *one_card = const_cast<Card *>(&(node->getCards()[i_card]));
                    uint64_t card_long = Card::boardInt2long(
                            one_card->getCardInt());
                    if (!Card::boardsHasIntercept(card_long, current_board)) {
                        multiplier_num += 1;
                    }
                } else {
                    Card *one_card = const_cast<Card *>(&(node->getCards()[i_card]));
                    uint64_t card_long = Card::boardInt2long(
                            one_card->getCardInt());
                    if (!Card::boardsHasIntercept(card_long, current_board)) {
                        multiplier_num += 1;
                    }
                }
            }
            multiplier[card_target] = multiplier_num;
        }
    }

    vector<int> valid_cards;
    valid_cards.reserve(node->getCards().size());

    for(int card = 0;card < node->getCards().size();card ++) {
        shared_ptr<GameTreeNode> one_child = node->getChildren();
        Card *one_card = const_cast<Card *>(&(node->getCards()[card]));
        uint64_t card_long = Card::boardInt2long(one_card->getCardInt());//Card::boardCards2long(new Card[]{one_card});
        if (Card::boardsHasIntercept(card_long, current_board)) continue;
        if (iter <= this->warmup && multiplier[card] == 0) continue;
        if (this->color_iso_offset[deal][one_card->getCardInt() % 4] < 0) continue;
        valid_cards.push_back(card);
    }

    #pragma omp parallel for schedule(static)
    for(int valid_ind = 0;valid_ind < valid_cards.size();valid_ind++) {
        int card = valid_cards[valid_ind];
        shared_ptr<GameTreeNode> one_child = node->getChildren();
        Card *one_card = const_cast<Card *>(&(node->getCards()[card]));
        uint64_t card_long = Card::boardInt2long(one_card->getCardInt());//Card::boardCards2long(new Card[]{one_card});

        uint64_t new_board_long = current_board | card_long;
        if (this->monteCarolAlg == MonteCarolAlg::PUBLIC) {
            throw runtime_error("parallel solver don't support public monte carol");
        }

        //cout << "Card deal:" << one_card->toString() << endl;

        vector<PrivateCards> &playerPrivateCard = (this->ranges[player]);
        vector<PrivateCards> &oppoPrivateCards = (this->ranges[1 - player]);


        sui::Scratch<float> reachScratch(oppoPrivateCards.size());
        auto& new_reach_probs=reachScratch.value;



#ifdef DEBUG
        if (playerPrivateCard.size() != this->ranges[player].size()) throw runtime_error("length not match");
        if (oppoPrivateCards.size() != this->ranges[1 - player].size()) throw runtime_error("length not match");
#endif

        int player_hand_len = this->ranges[oppo].size();
        for (int player_hand = 0; player_hand < player_hand_len; player_hand++) {
            PrivateCards &one_private = this->ranges[oppo][player_hand];
            uint64_t privateBoardLong = one_private.toBoardLong();
            if (Card::boardsHasIntercept(card_long, privateBoardLong)) {
                new_reach_probs[player_hand] = 0;
                continue;
            }
            new_reach_probs[player_hand] = reach_probs[player_hand] / possible_deals;
        }
#ifdef DEBUG
        if (Card::boardsHasIntercept(current_board, card_long))
            throw runtime_error("board has intercept with dealt card");
#endif

        int new_deal;
        if(deal == 0){
            new_deal = card + 1;
        } else if (deal > 0 && deal <= card_num){
            int origin_deal = deal - 1;

#ifdef DEBUG
            if(origin_deal == card) throw runtime_error("deal should not be equal");
#endif
            new_deal = card_num * origin_deal + card;
            new_deal += (1 + card_num);
        } else{
            throw runtime_error(fmt::format("deal out of range : {} ",deal));
        }
        if(this->distributing_task && node->getRound() == this->split_round) {
            results[one_card->getNumberInDeckInt()] = vector<float>(this->ranges[player].size());
            //TaskParams taskParams = TaskParams();
        }else {
            // Written for Sui by us: move the returned vector directly into its result slot.
            results[one_card->getNumberInDeckInt()] = this->cfr(player, one_child, new_reach_probs, iter, new_board_long, new_deal);
        }
    }

    for(int card = 0;card < node->getCards().size();card ++) {
        Card *one_card = const_cast<Card *>(&(node->getCards()[card]));
        // Written for Sui by us: borrow ordinary results; only suit permutation needs a copy.
        vector<float> permuted_utility;
        const vector<float>* utility = &results[one_card->getNumberInDeckInt()];
        int offset = this->color_iso_offset[deal][one_card->getCardInt() % 4];
        if(offset < 0) {
            int rank1 = one_card->getCardInt() % 4;
            int rank2 = rank1 + offset;
#ifdef DEBUG
            if(rank2 < 0) throw runtime_error("rank error");
#endif
            permuted_utility = results[one_card->getNumberInDeckInt() + offset];
            exchange_color(permuted_utility,this->pcm.getPreflopCards(player),rank1,rank2);
            utility = &permuted_utility;
        }
        const vector<float>& child_utility = *utility;
        if(child_utility.empty())
            continue;

#ifdef DEBUG
        if(child_utility.size() != chance_utility.size()) throw runtime_error("length not match");
#endif
        if(iter > this->warmup) {
            for (int i = 0; i < child_utility.size(); i++)
                chance_utility[i] += child_utility[i];
        }else{
            for (int i = 0; i < child_utility.size(); i++)
                chance_utility[i] += child_utility[i] * multiplier[card];
        }
    }

#ifdef DEBUG
    if(this->monteCarolAlg == MonteCarolAlg::PUBLIC) {
        throw runtime_error("not possible");
    }
    if(chance_utility.size() != this->ranges[player].size()) {
        throw runtime_error("size problems");
    }
#endif
    return chance_utility;
}

vector<float>
PCfrSolver::actionUtility(int player, shared_ptr<ActionNode> node, const vector<float> &reach_probs, int iter,
                         uint64_t current_board,int deal) {
    int oppo = 1 - player;
    const vector<PrivateCards>& node_player_private_cards = this->ranges[node->getPlayer()];

    vector<float> payoffs = vector<float>(this->ranges[player].size());
    fill(payoffs.begin(),payoffs.end(),0);
    vector<shared_ptr<GameTreeNode>>& children =  node->getChildrens();
    vector<GameActions>& actions =  node->getActions();

    shared_ptr<Trainable> trainableOwner;
    Trainable* trainable;

    /*
    if(iter <= this->warmup){
        vector<int> deals = this->getAllAbstractionDeal(deal);
        trainable = node->getTrainable(deals[0]);
    }else{
        trainableOwner=sui::options.borrowState?nullptr:node->getTrainable(deal);
    trainable=sui::options.borrowState?node->borrowTrainable(deal):trainableOwner.get();
    }
     */
    trainableOwner=sui::options.borrowState?nullptr:node->getTrainable(deal);
    trainable=sui::options.borrowState?node->borrowTrainable(deal):trainableOwner.get();

#ifdef DEBUG
    if(trainable == nullptr){
        throw runtime_error("null trainable");
    }
#endif

    const vector<float> current_strategy = trainable->getcurrentStrategy();
#ifdef DEBUG
    if (current_strategy.size() != actions.size() * node_player_private_cards.size()) {
        node->printHistory();
        throw runtime_error(fmt::format(
                "length not match {} - {} \n action size {} private_card size {}"
                ,current_strategy.size()
                ,actions.size() * node_player_private_cards.size()
                ,actions.size()
                ,node_player_private_cards.size()
        ));
    }
#endif

    //为了节省计算成本将action regret 存在一位数组而不是二维数组中，两个纬度分别是（该infoset有多少动作,该palyer有多少holecard）
    // Written for Sui by us: regrets are allocated only for the updating player below;
    // results already owns each action utility, so no duplicate utility matrix is needed.
    int node_player = node->getPlayer();

    const bool stream=sui::options.stream && node_player!=player;
    vector<vector<float>> results(stream?1:actions.size());
    // Written for Sui by us: sibling actions run sequentially; reuse this call-local buffer.
    sui::Scratch<float> reachScratch(node_player != player ? reach_probs.size() : 0);
    auto& new_reach_prob=reachScratch.value;
    for (int action_id = 0; action_id < actions.size(); action_id++) {

        if (node_player != player) {
            for (int hand_id = 0; hand_id < new_reach_prob.size(); hand_id++) {
                float strategy_prob = current_strategy[hand_id + action_id * node_player_private_cards.size()];
                new_reach_prob[hand_id] = reach_probs[hand_id] * strategy_prob;
            }
            //#pragma omp task shared(results,action_id)
            results[stream?0:action_id] = this->cfr(player, children[action_id], new_reach_prob, iter,
                                           current_board,deal);
        }else {
            //#pragma omp task shared(results,action_id)
            results[action_id] = this->cfr(player, children[action_id], reach_probs, iter,
                                           current_board,deal);
        }

        if(stream)for(size_t h=0;h<payoffs.size();++h)payoffs[h]+=results[0][h];
    }
    if(stream)return payoffs;

    //#pragma omp taskwait
    for (int action_id = 0; action_id < actions.size(); action_id++) {
        // Written for Sui by us: read the existing result without copying it.
        const vector<float>& action_utilities = results[action_id];
        if(action_utilities.empty()){
            continue;
        }
        // Written for Sui by us: results retains the values needed for regret updates.

        // cfr结果是每手牌的收益，payoffs代表的也是每手牌的收益，他们的长度理应相等
#ifdef DEBUG
        if (action_utilities.size() != payoffs.size()) {
            cout << ("errmsg") << endl;
            cout << (fmt::format("node player {} ", node->getPlayer())) << endl;
            node->printHistory();
            throw runtime_error(
                    fmt::format(
                            "action and payoff length not match {} - {}", action_utilities.size(),
                            payoffs.size()
                    )
            );
        }
#endif

        for (int hand_id = 0; hand_id < action_utilities.size(); hand_id++) {
            if (player == node->getPlayer()) {
                float strategy_prob = current_strategy[hand_id + action_id * node_player_private_cards.size()];
                payoffs[hand_id] += strategy_prob * (action_utilities)[hand_id];
            } else {
                payoffs[hand_id] += (action_utilities)[hand_id];
            }
        }
    }


    if (player == node->getPlayer()) {
        // Written for Sui by us: opponent nodes never consume a regret buffer.
        sui::Scratch<float> regretScratch(actions.size()*node_player_private_cards.size());
        auto& regrets=regretScratch.value;
        for (int i = 0; i < node_player_private_cards.size(); i++) {
            //boolean regrets_all_negative = true;
            for (int action_id = 0; action_id < actions.size(); action_id++) {
                // 下面是regret计算的伪代码
                // regret[action_id * player_hc: (action_id + 1) * player_hc]
                //     = all_action_utilitiy[action_id] - payoff[action_id]
                regrets[action_id * node_player_private_cards.size() + i] =
                        (results[action_id])[i] - payoffs[i];
            }
        }

        if(!this->distributing_task) {
            if (iter > this->warmup) {
                trainable->updateRegrets(regrets, iter + 1, reach_probs);
            }/*else if(iter < this->warmup){
            vector<int> deals = this->getAllAbstractionDeal(deal);
            shared_ptr<Trainable> one_trainable = node->getTrainable(deals[0]);
            one_trainable->updateRegrets(regrets, iter + 1, reach_probs[player]);
            }*/
            else {
                // iter == this->warmup
                vector<int> deals = this->getAllAbstractionDeal(deal);
                shared_ptr<Trainable> standard_trainable = nullptr;
                for (int one_deal : deals) {
                    shared_ptr<Trainable> one_trainable = node->getTrainable(one_deal);
                    if (standard_trainable == nullptr) {
                        one_trainable->updateRegrets(regrets, iter + 1, reach_probs);
                        standard_trainable = one_trainable;
                    } else {
                        one_trainable->copyStrategy(standard_trainable);
                    }
                }
            }
        }
    }
    return payoffs;

}

vector<float>
PCfrSolver::showdownUtility(int player, shared_ptr<ShowdownNode> node, const vector<float> &reach_probs,
                           int iter, uint64_t current_board,int deal) {
    // player win时候player的收益，player lose的时候收益明显为-player_payoff
    int oppo = 1 - player;
    float win_payoff = node->get_payoffs(ShowdownNode::ShowDownResult::NOTTIE,player,player);
    float lose_payoff = node->get_payoffs(ShowdownNode::ShowDownResult::NOTTIE,oppo,player);
    const vector<PrivateCards>& player_private_cards = this->ranges[player];
    const vector<PrivateCards>& oppo_private_cards = this->ranges[oppo];

    const auto player_combs = this->rrm.getRiverCombos(player,player_private_cards,current_board);
    const auto oppo_combs = this->rrm.getRiverCombos(oppo,oppo_private_cards,current_board);

    vector<float> payoffs = vector<float>(player_private_cards.size());

    float winsum = 0;
    sui::CardSums card_winsum(sui::options.stack);//node->card_sum;
    fill(card_winsum.begin(),card_winsum.end(),0);

    int j = 0;
    for(int i = 0;i < player_combs.size();i ++){
        const auto& one_player_comb = player_combs[i];
        while (j < oppo_combs.size() && one_player_comb.rank < oppo_combs[j].rank){
            const auto& one_oppo_comb = oppo_combs[j];
            winsum += reach_probs[one_oppo_comb.reach_prob_index];
            card_winsum[one_oppo_comb.private_cards.card1] += reach_probs[one_oppo_comb.reach_prob_index];
            card_winsum[one_oppo_comb.private_cards.card2] += reach_probs[one_oppo_comb.reach_prob_index];
            j ++;
        }
        payoffs[one_player_comb.reach_prob_index] = (winsum
                                                     - card_winsum[one_player_comb.private_cards.card1]
                                                     - card_winsum[one_player_comb.private_cards.card2]
                                                    ) * win_payoff;
    }

    // 计算失败时的payoff
    float losssum = 0;
    auto& card_losssum = card_winsum;
    fill(card_losssum.begin(),card_losssum.end(),0);

    j = oppo_combs.size() - 1;
    for(int i = player_combs.size() - 1;i >= 0;i --){
        const auto& one_player_comb = player_combs[i];
        while (j >= 0 && one_player_comb.rank > oppo_combs[j].rank){
            const auto& one_oppo_comb = oppo_combs[j];
            losssum += reach_probs[one_oppo_comb.reach_prob_index];
            card_losssum[one_oppo_comb.private_cards.card1] += reach_probs[one_oppo_comb.reach_prob_index];
            card_losssum[one_oppo_comb.private_cards.card2] += reach_probs[one_oppo_comb.reach_prob_index];
            j --;
        }
        payoffs[one_player_comb.reach_prob_index] += (losssum
                                                      - card_losssum[one_player_comb.private_cards.card1]
                                                      - card_losssum[one_player_comb.private_cards.card2]
                                                     ) * lose_payoff;
    }
    return payoffs;
}

vector<float>
PCfrSolver::terminalUtility(int player, shared_ptr<TerminalNode> node, const vector<float> &reach_prob, int iter,
                           uint64_t current_board,int deal) {
    float player_payoff = sui::options.scalar ? node->payoff(player) : node->get_payoffs()[player];

    int oppo = 1 - player;
    const vector<PrivateCards>& player_hand = playerHands(player);
    const vector<PrivateCards>& oppo_hand = playerHands(oppo);

    vector<float> payoffs = vector<float>(this->playerHands(player).size());

    float oppo_sum = 0;
    sui::CardSums oppo_card_sum(sui::options.stack);
    fill(oppo_card_sum.begin(),oppo_card_sum.end(),0);

    for(int i = 0;i < oppo_hand.size();i ++){
        oppo_card_sum[oppo_hand[i].card1] += reach_prob[i];
        oppo_card_sum[oppo_hand[i].card2] += reach_prob[i];
        oppo_sum += reach_prob[i];
    }

    for(int i = 0;i < player_hand.size();i ++){
        const PrivateCards& one_player_hand = player_hand[i];
        if(Card::boardsHasIntercept(current_board,(sui::options.masks ? one_player_hand.toBoardLong() : Card::boardInts2long(one_player_hand.get_hands())))){
            continue;
        }
        int oppo_same_card_ind = this->pcm.indPlayer2Player(player,oppo,i);
        float plus_reach_prob;
        if(oppo_same_card_ind == -1){
            plus_reach_prob = 0;
        }else{
            plus_reach_prob = reach_prob[oppo_same_card_ind];
        }
        payoffs[i] = player_payoff * (
                oppo_sum - oppo_card_sum[one_player_hand.card1]
                - oppo_card_sum[one_player_hand.card2]
                + plus_reach_prob
        );
    }

    return payoffs;
}

void PCfrSolver::findGameSpecificIsomorphisms() {
    // hand isomorphisms
    vector<Card> board_cards = Card::long2boardCards(this->initial_board_long);
    for(int i = 0;i <= 1;i ++){
        vector<PrivateCards>& range = i == 0?this->range1:this->range2;
        for(int i_range = 0;i_range < range.size();i_range ++) {
            PrivateCards one_range = range[i_range];
            uint32_t range_hash[4]; // four colors, hash of the isomorphisms range + hand combos
            for(int i = 0;i < 4;i ++)range_hash[i] = 0;
            for (int color = 0; color < 4; color++) {
                for (Card one_card:board_cards) {
                    if (one_card.getCardInt() % 4 == color) {
                        range_hash[color] = range_hash[color] | (1 << (one_card.getCardInt() / 4));
                    }
                }
            }
            for (int color = 0; color < 4; color++) {
                for (int one_card_int:{one_range.card1,one_range.card2}) {
                    if (one_card_int % 4 == color) {
                        range_hash[color] = range_hash[color] | (1 << (one_card_int / 4 + 16));
                    }
                }
            }
            // TODO check whethe hash is equal with others
        }
    }

    // chance node isomorphisms
    uint16_t color_hash[4];
    for(int i = 0;i < 4;i ++)color_hash[i] = 0;
    for (Card one_card:board_cards) {
        int rankind = one_card.getCardInt() % 4;
        int suitind = one_card.getCardInt() / 4;
        color_hash[rankind] = color_hash[rankind] | (1 << suitind);
    }
    for(int i = 0;i < 4;i ++){
        this->color_iso_offset[0][i] = 0;
        for(int j = 0;j < i;j ++){
            if(color_hash[i] == color_hash[j]){
                this->color_iso_offset[0][i] = j - i;
                continue;
            }
        }
    }
    for(int deal = 0;deal < this->deck.getCards().size();deal ++) {
        uint16_t color_hash[4];
        for(int i = 0;i < 4;i ++)color_hash[i] = 0;
        // chance node isomorphisms
        for (Card one_card:board_cards) {
            int rankind = one_card.getCardInt() % 4;
            int suitind = one_card.getCardInt() / 4;
            color_hash[rankind] = color_hash[rankind] | (1 << suitind);
        }
        Card one_card = this->deck.getCards()[deal];
        int rankind = one_card.getCardInt() % 4;
        int suitind = one_card.getCardInt() / 4;
        color_hash[rankind] = color_hash[rankind] | (1 << suitind);
        for (int i = 0; i < 4; i++) {
            this->color_iso_offset[deal + 1][i] = 0;
            for (int j = 0; j < i; j++) {
                if (color_hash[i] == color_hash[j]) {
                    this->color_iso_offset[deal + 1][i] = j - i;
                    continue;
                }
            }
        }
    }
}

void PCfrSolver::purnTree() {
    // TODO how to purn the tree, use wramup to start training in memory-save mode, and switch to purn tree directly to both save memory and speedup
}

void PCfrSolver::train() {

    vector<vector<PrivateCards>> player_privates(this->player_number);
    player_privates[0] = pcm.getPreflopCards(0);
    player_privates[1] = pcm.getPreflopCards(1);
    if(this->use_isomorphism){
        this->findGameSpecificIsomorphisms();
    }

    if((!sui::checkpointPath.empty()||!sui::resumePath.empty())&&(warmup>0||monteCarolAlg!=MonteCarolAlg::NONE))throw runtime_error("Checkpointing requires deterministic full-tree training with warmup<=0");
    int completed=sui::resumePath.empty()?0:restoreCheckpoint();
    BestResponse br = BestResponse(player_privates,this->player_number,this->pcm,this->rrm,this->deck,this->debug,this->color_iso_offset,this->split_round,this->num_threads);

    auto setupStarted=sui::now();
    br.printExploitability(tree->getRoot(), 0, tree->getRoot()->getPot(), initial_board_long);
    sui::phase("initial_best_response",setupStarted);

    vector<vector<float>> reach_probs = this->getReachProbs();
    ofstream fileWriter;
    if(!this->logfile.empty())fileWriter.open(this->logfile);

    uint64_t begintime = timeSinceEpochMillisec();
    uint64_t endtime = timeSinceEpochMillisec();

    int checkInterval=this->print_interval;
    int lastChecked=completed;
    bool stoppedEarly=false;
    for(int i = completed;i < this->iteration_number;i++){
        if(completed>0)if(const char* path=std::getenv("SUI_SOLVER_STOP_PATH")){
            if(access(path,F_OK)==0){stoppedEarly=true;break;}
        }
        auto iterationStarted=sui::now();
        for(int player_id = 0;player_id < this->player_number;player_id ++) {
            this->round_deal = vector<int>{-1,-1,-1,-1};
            //#pragma omp parallel
            {
                //#pragma omp single
                {
                    //this->distributing_task = true;
                    cfr(player_id, this->tree->getRoot(), reach_probs[1 - player_id], i, this->initial_board_long,0);
                    //throw runtime_error("returning...");
                }
            }
        }
        completed=i+1;
        if(std::getenv("SUI_SOLVER_PREVIEW_PATH"))cout<<"SUI_ITERATION: "<<completed<<endl;
        // Only the visible root range, after both player traversals have joined.
        // Atomic replacement lets the UI read the latest complete animation frame.
        if(const char* path=std::getenv("SUI_SOLVER_PREVIEW_PATH")){
            auto root=std::static_pointer_cast<ActionNode>(tree->getRoot());
            auto state=root->getTrainable(0,false);
            if(state){
                json frame;frame["node_type"]="action_node";frame["player"]=root->getPlayer();
                vector<string> actions;for(auto&action:root->getActions())actions.push_back(action.toString());
                frame["actions"]=actions;frame["strategy"]=state->dump_strategy(false);frame["iteration"]=completed;
                string temporary=string(path)+".tmp";
                {ofstream out(temporary,ios::binary|ios::trunc);out<<frame;out.close();
                 if(out)rename(temporary.c_str(),path);else unlink(temporary.c_str());}
            }
        }
        if(const char* path=std::getenv("SUI_SOLVER_STOP_PATH")){
            if(access(path,F_OK)==0){stoppedEarly=true;break;}
        }
        if(sui::checkpointEvery&&completed%sui::checkpointEvery==0)saveCheckpoint(completed);
        sui::phase("cfr_iteration",iterationStarted);
        if(((i % checkInterval == 0 && i != 0) || (sui::options.adaptive && i+1==iteration_number)) && i >= this->warmup) {
            auto checkStarted=sui::now();
            endtime = timeSinceEpochMillisec();
            long time_ms = endtime - begintime;
            cout << ("-------------------") << endl;
            lastChecked=completed;
            float expliotibility = br.printExploitability(tree->getRoot(), i + 1, tree->getRoot()->getPot(), initial_board_long);
            sui::phase("best_response",checkStarted);
            if(sui::options.adaptive && expliotibility>accuracy*4)checkInterval=min(40,max(print_interval,checkInterval*2));
            else checkInterval=print_interval;
            cout << "time used: " << float(time_ms) / 1000 << endl;
            if(!this->logfile.empty()){
                json jo;
                jo["iteration"] = i;
                jo["exploitibility"] = expliotibility;
                jo["time_ms"] = time_ms;
                fileWriter << jo << endl;
            }
            if(expliotibility <= this->accuracy){
                break;
            }
            //begintime = timeSinceEpochMillisec();
        }
    }
    if(stoppedEarly && lastChecked!=completed){
        float value=br.printExploitability(tree->getRoot(),completed,tree->getRoot()->getPot(),initial_board_long);
        if(!logfile.empty())fileWriter<<json{{"iteration",completed-1},{"exploitibility",value}}<<endl;
    }
    if(!sui::checkpointPath.empty())saveCheckpoint(completed);
    if(!this->logfile.empty()) {
        fileWriter.flush();
        fileWriter.close();
    }

}

void PCfrSolver::exchangeRange(json& strategy,int rank1,int rank2,shared_ptr<ActionNode> one_node){
    if(rank1 == rank2)return;
    int player = one_node->getPlayer();
    vector<string> range_strs;
    vector<vector<float>> strategies;

    for(int i = 0;i < this->ranges[player].size();i ++){
        string one_range_str = this->ranges[player][i].toString();
        if(!strategy.contains(one_range_str)){
            for(auto one_key:strategy.items()){
                cout << one_key.key() << endl;
            }
            cout << "strategy: " << strategy  << endl;
            throw runtime_error(fmt::format("{} not exist in strategy",one_range_str));
        }
        vector<float> one_strategy = strategy[one_range_str];
        range_strs.push_back(one_range_str);
        strategies.push_back(one_strategy);
    }
    exchange_color(strategies,this->ranges[player],rank1,rank2);

    for(int i = 0;i < this->ranges[player].size();i ++) {
        string one_range_str = this->ranges[player][i].toString();
        vector<float> one_strategy = strategies[i];
        strategy[one_range_str] = one_strategy;
    }
}

void PCfrSolver::filterColliding(json& strategy_block,uint64_t current_board_long) {
    if(!strategy_block.contains("strategy")) return;
    json& combo_map = strategy_block["strategy"];
    if(!combo_map.is_object()) return;
    vector<string> to_drop;
    for(auto it = combo_map.begin();it != combo_map.end();++ it){
        const string& combo = it.key();
        if(combo.size() < 4) continue;
        vector<string> hole{combo.substr(0,2),combo.substr(2,2)};
        uint64_t hole_long = Card::boardCards2long(hole);
        if(Card::boardsHasIntercept(hole_long,current_board_long)){
            to_drop.push_back(combo);
        }
    }
    for(const string& combo : to_drop) combo_map.erase(combo);
}

void PCfrSolver::reConvertJson(const shared_ptr<GameTreeNode>& node,json& strategy,string key,int depth,int max_depth,vector<string> prefix,int deal,vector<vector<int>> exchange_color_list,uint64_t current_board_long) {
    if(depth >= max_depth) return;
    if(node->getType() == GameTreeNode::GameTreeNodeType::ACTION) {
        json* retval;
        if(key != ""){
            strategy[key] = json();
            retval = &(strategy[key]);
        }else{
            retval = &strategy;
        }

        shared_ptr<ActionNode> one_node = (sui::options.dispatch ? std::static_pointer_cast<ActionNode>(node) : std::dynamic_pointer_cast<ActionNode>(node));

        vector<string> actions_str;
        for(GameActions one_action:one_node->getActions()) actions_str.push_back(one_action.toString());

        (*retval)["actions"] = actions_str;
        (*retval)["player"] = one_node->getPlayer();

        (*retval)["childrens"] = json();
        json& childrens = (*retval)["childrens"];

        for(int i = 0;i < one_node->getActions().size();i ++){
            GameActions& one_action = one_node->getActions()[i];
            shared_ptr<GameTreeNode> one_child = one_node->getChildrens()[i];
            vector<string> new_prefix(prefix);
            new_prefix.push_back(one_action.toString());
            this->reConvertJson(one_child,childrens,one_action.toString(),depth,max_depth,new_prefix,deal,exchange_color_list,current_board_long);
        }
        if((*retval)["childrens"].empty()){
            (*retval).erase("childrens");
        }
        shared_ptr<Trainable> trainable = one_node->getTrainable(deal,false);
        if(trainable != nullptr) {
            (*retval)["strategy"] = trainable->dump_strategy(false);
            for(vector<int> one_exchange:exchange_color_list){
                int rank1 = one_exchange[0];
                int rank2 = one_exchange[1];
                this->exchangeRange((*retval)["strategy"]["strategy"],rank1,rank2,one_node);

            }
            PCfrSolver::filterColliding((*retval)["strategy"],current_board_long);
        }
        (*retval)["node_type"] = "action_node";

    }else if(node->getType() == GameTreeNode::GameTreeNodeType::SHOWDOWN) {
    }else if(node->getType() == GameTreeNode::GameTreeNodeType::TERMINAL) {
    }else if(node->getType() == GameTreeNode::GameTreeNodeType::CHANCE) {
        json* retval;
        if(key != ""){
            strategy[key] = json();
            retval = &(strategy[key]);
        }else{
            retval = &strategy;
        }

        shared_ptr<ChanceNode> chanceNode = (sui::options.dispatch ? std::static_pointer_cast<ChanceNode>(node) : std::dynamic_pointer_cast<ChanceNode>(node));
        const vector<Card>& cards = chanceNode->getCards();
        shared_ptr<GameTreeNode> childerns = chanceNode->getChildren();
        vector<string> card_strs;
        for(Card card:cards)
            card_strs.push_back(card.toString());

        json& dealcards = (*retval)["dealcards"];
        for(int i = 0;i < cards.size();i ++){
            vector<vector<int>> new_exchange_color_list(exchange_color_list);
            Card& one_card = const_cast<Card &>(cards[i]);
            vector<string> new_prefix(prefix);
            new_prefix.push_back("Chance:" + one_card.toString());

            int card = i;

            int offset = this->color_iso_offset[deal][one_card.getCardInt() % 4];
            if(offset < 0) {
                for(int x = 0;x < cards.size();x ++){
                    if(
                            Card::card2int(cards[x]) ==
                            (Card::card2int(cards[card]) + offset)
                    ){
                        card = x;
                        break;
                    }
                }
                if(card == i){
                    throw runtime_error("isomorphism not found while dump strategy");
                }
                vector<int> one_exchange{one_card.getCardInt() % 4,one_card.getCardInt() % 4 + offset};
                new_exchange_color_list.push_back(one_exchange);
            }

            int card_num = this->deck.getCards().size();
            int new_deal;
            if(deal == 0){
                new_deal = card + 1;
            } else if (deal > 0 && deal <= card_num){
                int origin_deal = deal - 1;

#ifdef DEBUG
                if(origin_deal == card) throw runtime_error("deal should not be equal");
#endif
                new_deal = card_num * origin_deal + card;
                new_deal += (1 + card_num);
            } else{
                throw runtime_error(fmt::format("deal out of range : {} ",deal));
            }

            if(exchange_color_list.size() > 1){
                throw runtime_error("exchange color list shouldn't be exceed size 1 here");
            }

            string one_card_str = one_card.toString();
            if(exchange_color_list.size() == 1) {
                int rank1 = exchange_color_list[0][0];
                int rank2 = exchange_color_list[0][1];
                if(one_card.getCardInt() % 4 == rank1){
                    one_card_str = Card::intCard2Str(one_card.getCardInt() - rank1 + rank2);
                }else if(one_card.getCardInt() % 4 == rank2){
                    one_card_str = Card::intCard2Str(one_card.getCardInt() - rank2 + rank1);
                }

            }

            // Extend the board mask with the chance card actually written into the
            // JSON (after color isomorphism). Subtrees rooted here will use this to
            // drop combos that physically collide with the runout.
            uint64_t child_board_long = current_board_long | Card::boardCards2long(vector<string>{one_card_str});

            this->reConvertJson(childerns,dealcards,one_card_str,depth + 1,max_depth,new_prefix,new_deal,new_exchange_color_list,child_board_long);
        }
        if((*retval)["dealcards"].empty()){
            (*retval).erase("dealcards");
        }

        (*retval)["deal_number"] = dealcards.size();
        (*retval)["node_type"] = "chance_node";
    }else{
        throw runtime_error("node type unknown!!");
    }
}

json PCfrSolver::dumps(bool with_status,int depth) {
    if(with_status == true){
        throw runtime_error("");
    }
    json retjson;
    this->reConvertJson(this->tree->getRoot(),retjson,"",0,depth,vector<string>({"begin"}),0,vector<vector<int>>(),this->initial_board_long);
    if(const char* enabled=std::getenv("SUI_SOLVER_EXPORT_EV"); enabled && string(enabled)=="1") {
        cout << "Evaluating strategy EVs" << endl;
        BestResponse evaluator(ranges,player_number,pcm,rrm,deck,false,color_iso_offset,split_round,num_threads);
        const auto values=evaluator.policyEvs(tree->getRoot(),initial_board_long);
        std::function<void(shared_ptr<GameTreeNode>,json&)> attach = [&](shared_ptr<GameTreeNode> node,json& out) {
            if(node->getType()!=GameTreeNode::ACTION || !out.is_object()) return;
            auto found=values.find(node.get());
            if(found!=values.end()) { out["ev"]=found->second["ev"]; out["ev_mass"]=found->second["ev_mass"]; }
            auto action=std::static_pointer_cast<ActionNode>(node);
            for(size_t i=0;i<action->getActions().size();++i) {
                auto key=action->getActions()[i].toString();
                if(out.contains("childrens") && out["childrens"].contains(key)) attach(action->getChildrens()[i],out["childrens"][key]);
            }
        };
        attach(tree->getRoot(),retjson);
    }
    return std::move(retjson);
}

namespace {
void eachPacked(const shared_ptr<GameTreeNode> &node,
                const std::function<void(PackedStore &)> &visit) {
  if (node->getType() == GameTreeNode::ACTION) {
    auto action = std::static_pointer_cast<ActionNode>(node);
    auto store = action->packedStore();
    if (!store)
      throw runtime_error("Checkpoint requires packed state");
    visit(*store);
    for (auto &child : action->getChildrens())
      eachPacked(child, visit);
  } else if (node->getType() == GameTreeNode::CHANCE)
    eachPacked(std::static_pointer_cast<ChanceNode>(node)->getChildren(),
               visit);
}
uint64_t identityHash(const string &s) {
  uint64_t h = 14695981039346656037ULL;
  for (unsigned char c : s) {
    h ^= c;
    h *= 1099511628211ULL;
  }
  return h;
}
} // namespace
string PCfrSolver::checkpointIdentity() {
  json identity;
  identity["version"] = "sui-dcfr-1";
  identity["warmup"] = warmup;
  identity["board"] = initial_board_long;
  identity["blocked"] = sui::options.blocked;
  identity["canonicalSlabs"] = sui::options.canonicalSlabs;
  identity["halfAverage"] = sui::options.halfAverage;
  identity["halfRegret"] = sui::options.halfRegret;
  identity["isomorphism"] = use_isomorphism;
  identity["coefficient_format"] =
      "alpha=1.5,beta=.5,gamma=2,theta=.9,float32-arithmetic";
  for (int p = 0; p < 2; ++p)
    for (auto &hand : ranges[p])
      identity["ranges"][p].push_back({hand.card1, hand.card2, hand.weight});
  for (auto &card : deck.getCards())
    identity["deck"].push_back(card.getCardInt());
  std::function<void(shared_ptr<GameTreeNode>)> append =
      [&](shared_ptr<GameTreeNode> node) {
        json item = {{"kind", node->getType()},
                     {"round", node->getRound()},
                     {"pot", node->getPot()}};
        if (node->getType() == GameTreeNode::ACTION) {
          auto a = std::static_pointer_cast<ActionNode>(node);
          item["player"] = a->getPlayer();
          for (auto &x : a->getActions())
            item["actions"].push_back({x.getAction(), x.getAmount()});
          identity["nodes"].push_back(item);
          for (auto &child : a->getChildrens())
            append(child);
        } else if (node->getType() == GameTreeNode::CHANCE) {
          auto c = std::static_pointer_cast<ChanceNode>(node);
          item["donk"] = c->isDonk();
          identity["nodes"].push_back(item);
          append(c->getChildren());
        } else {
          if (node->getType() == GameTreeNode::TERMINAL) {
            auto t = std::static_pointer_cast<TerminalNode>(node);
            item["payoffs"] = t->get_payoffs();
          } else {
            auto t = std::static_pointer_cast<ShowdownNode>(node);
            for (int w = 0; w < 2; ++w)
              for (int p = 0; p < 2; ++p)
                item["payoffs"].push_back(
                    t->get_payoffs(ShowdownNode::NOTTIE, w, p));
          }
          identity["nodes"].push_back(item);
        }
      };
  append(tree->getRoot());
  return identity.dump();
}
void PCfrSolver::saveCheckpoint(int completed) {
  auto started = sui::now();
  string pattern = sui::checkpointPath + ".tmp.XXXXXX";
  vector<char> name(pattern.begin(), pattern.end());
  name.push_back(0);
  int fd = mkstemp(name.data());
  if (fd < 0)
    throw runtime_error("Cannot create checkpoint temporary file");
  close(fd);
  try {
    ofstream out(name.data(), ios::binary | ios::trunc);
    string identity = checkpointIdentity();
    uint64_t size = identity.size(),
             hash = identityHash(identity + to_string(completed));
    uint32_t endian = 0x01020304, iteration = completed;
    out.write("SUISTATE1", 9);
    out.write(reinterpret_cast<char *>(&endian), 4);
    out.write(reinterpret_cast<char *>(&iteration), 4);
    out.write(reinterpret_cast<char *>(&size), 8);
    out.write(reinterpret_cast<char *>(&hash), 8);
    out.write(identity.data(), size);
    eachPacked(tree->getRoot(),
               [&](PackedStore &store) { store.checkpoint(out); });
    out.flush();
    if (!out)
      throw runtime_error("Checkpoint flush failed");
    out.close();
    fd = open(name.data(), O_RDONLY);
    if (fd < 0)
      throw runtime_error("Cannot sync checkpoint");
    int synced = fsync(fd);
    close(fd);
    if (synced)
      throw runtime_error("Checkpoint sync failed");
    if (rename(name.data(), sui::checkpointPath.c_str()))
      throw runtime_error("Cannot publish checkpoint");
  } catch (...) {
    unlink(name.data());
    throw;
  }
  cout << "SUI_CHECKPOINT: completed=" << completed << endl;
  sui::phase("checkpoint", started);
}
int PCfrSolver::restoreCheckpoint() {
  ifstream in(sui::resumePath, ios::binary);
  char magic[9]{};
  uint32_t endian = 0, iteration = 0;
  uint64_t size = 0, hash = 0;
  in.read(magic, 9);
  in.read(reinterpret_cast<char *>(&endian), 4);
  in.read(reinterpret_cast<char *>(&iteration), 4);
  in.read(reinterpret_cast<char *>(&size), 8);
  in.read(reinterpret_cast<char *>(&hash), 8);
  if (!in || string(magic, 9) != "SUISTATE1" || endian != 0x01020304 ||
      size > 64 * 1024 * 1024 || iteration > uint32_t(iteration_number))
    throw runtime_error("Invalid/incompatible checkpoint header");
  string identity(size, '\0');
  in.read(identity.data(), size);
  if (!in || identityHash(identity + to_string(iteration)) != hash ||
      identity != checkpointIdentity())
    throw runtime_error("Checkpoint tree, ranges or representation mismatch");
  eachPacked(tree->getRoot(), [&](PackedStore &store) { store.restore(in); });
  if (in.peek() != std::char_traits<char>::eof())
    throw runtime_error("Trailing checkpoint data");
  cout << "SUI_RESUMED: completed=" << iteration << endl;
  return iteration;
}
