#include "tools/SuiOptions.h"
//
// Created by Xuefeng Huang on 2020/1/29.
//

#include "compairer/Dic5Compairer.h"

#include <climits>
#include <numeric>
#include <random>
#include <utility>

Dic5Compairer::Dic5Compairer(string dic_dir, int lines)
    : Compairer(std::move(dic_dir), lines) {
  if (sui::options.dense) {
    denseRanks.assign(2598960, UINT16_MAX);
    ifstream input(this->dic_dir);
    if (!input)
      throw runtime_error("Cannot open evaluator dictionary");
    string line;
    size_t count = 0;
    while (getline(input, line)) {
      auto comma = line.find(',');
      if (comma == string::npos)
        throw runtime_error("Malformed rank dictionary");
      uint64_t mask = 0;
      size_t start = 0;
      while (start < comma) {
        if (start + 2 > comma)
          throw runtime_error("Malformed dictionary card");
        int card = Card::strCard2int(line.substr(start, 2));
        if (mask & (uint64_t(1) << card))
          throw runtime_error("Repeated dictionary card");
        mask |= uint64_t(1) << card;
        start += 3;
      }
      int rank = stoi(line.substr(comma + 1));
      if (__builtin_popcountll(mask) != 5 || rank < 0 || rank >= UINT16_MAX)
        throw runtime_error("Invalid dictionary rank");
      auto index = denseIndex(mask);
      if (denseRanks.at(index) != UINT16_MAX)
        throw runtime_error("Repeated dictionary hand");
      denseRanks[index] = uint16_t(rank);
      ++count;
    }
    if (count != size_t(lines - 1))
      throw runtime_error("Incomplete evaluator dictionary");
    return;
  }
  ifstream infile(this->dic_dir);
  string line;
  progressbar bar(lines / 1000);
  int i = 0;
  while (std::getline(infile, line)) {
    vector<string> linesp = string_split(line, ',');
    if (linesp.size() != 2)
      throw runtime_error(fmt::format("linesp not correct: {}", line));

    string cards_str = linesp[0];
    int rank = stoi(linesp[1]);
    vector<string> cards = string_split(cards_str, '-');

    if (cards.size() != 5)
      throw runtime_error(fmt::format("cards not correct: {} length {}",
                                      cards_str, cards.size()));

    // set<string> cards_set;
    // for(string one_card:cards) cards_set.insert(one_card);
    // this->card2rank[cards_set] = rank;

    if (this->cardslong2rank.find(Card::boardCards2long(cards)) !=
        this->cardslong2rank.end()) {
      throw runtime_error(fmt::format("key repeated: {}", cards_str));
    }

    this->cardslong2rank[Card::boardCards2long(cards)] = rank;

    i++;
    if (i % 1000 == 0) {
      bar.update();
    }
  }
  cout << endl;
}

Compairer::CompairResult Dic5Compairer::compairRanks(int rank_former, int rank_latter) {
    if (rank_former < rank_latter) {
        // rank更小的牌更大，0是同花顺
        return CompairResult::LARGER;
    } else if (rank_former > rank_latter) {
        return CompairResult::SMALLER;
    } else {
        // rank_former == rank_latter
        return CompairResult::EQUAL;
    }
}

Compairer::CompairResult
Dic5Compairer::compair(vector<Card> private_former, vector<Card> private_latter, vector<Card> public_board) {
    if(private_former.size() != 2)
        throw runtime_error(
                fmt::format("private former size incorrect,excepted 2, actually {}",private_former.size())
                );
    if(private_latter.size() != 2)
        throw runtime_error(
                fmt::format("private latter size incorrect,excepted 2, actually {}",private_latter.size())
        );
    if(public_board.size() != 5)
        throw runtime_error(
                fmt::format("public board size incorrect,excepted 2, actually {}",public_board.size())
        );

    vector<Card> former_cards(private_former);
    former_cards.insert(former_cards.end(),public_board.begin(),public_board.end());
    int rank_former = this->getRank(former_cards);

    vector<Card> latter_cards(private_latter);
    latter_cards.insert(latter_cards.end(),public_board.begin(),public_board.end());
    int rank_latter = this->getRank(latter_cards);

    return this->compairRanks(rank_former,rank_latter);
}

Compairer::CompairResult
Dic5Compairer::compair(vector<int> private_former, vector<int> private_latter, vector<int> public_board) {
    if(private_former.size() != 2)
        throw runtime_error(
                fmt::format("private former size incorrect,excepted 2, actually {}",private_former.size())
        );
    if(private_latter.size() != 2)
        throw runtime_error(
                fmt::format("private latter size incorrect,excepted 2, actually {}",private_latter.size())
        );
    if(public_board.size() != 5)
        throw runtime_error(
                fmt::format("public board size incorrect,excepted 2, actually {}",public_board.size())
        );

    vector<int> former_cards(private_former);
    former_cards.insert(former_cards.end(),public_board.begin(),public_board.end());
    int rank_former = this->getRank(former_cards);

    vector<int> latter_cards(private_latter);
    latter_cards.insert(latter_cards.end(),public_board.begin(),public_board.end());
    int rank_latter = this->getRank(latter_cards);

    return this->compairRanks(rank_former,rank_latter);
}

int Dic5Compairer::getRank(vector<Card> cards) {
    vector<int> cards_int(cards.size());
    for(int i = 0;i < cards.size();i++){
        cards_int[i] = cards[i].getCardInt();
    }
    return this->getRank(cards_int);
}

int Dic5Compairer::getRank(vector<int> cards) {
    if(sui::options.dense) return denseRank(Card::boardInts2long(cards));
    Combinations<int> comb_cards(std::move(cards),5);
    int min_rank = numeric_limits<int>::max();
    for (const vector<int>& one_comb : comb_cards)
    {
        if(one_comb.size() != 5)throw runtime_error(fmt::format("card size incorrect: {} should be 5",one_comb.size()));
        uint64_t comb_uint64 = Card::boardInts2long(one_comb);
        int rank = this->cardslong2rank[comb_uint64];
        min_rank = min(rank,min_rank);
    }
    return min_rank;
}

int Dic5Compairer::get_rank(vector<Card> private_hand, vector<Card> public_board) {
    vector<Card> concatenate_vec(private_hand);
    concatenate_vec.insert(concatenate_vec.end(),public_board.begin(),public_board.end());
    return this->getRank(concatenate_vec);
}

int Dic5Compairer::get_rank(vector<int> private_hand, vector<int> public_board) {
    vector<int> concatenate_vec(private_hand);
    concatenate_vec.insert(concatenate_vec.end(),public_board.begin(),public_board.end());
    return this->getRank(concatenate_vec);
}

int Dic5Compairer::get_rank(uint64_t private_hand, uint64_t public_board) {
    if(sui::options.dense) return denseRank(private_hand|public_board);
    return this->get_rank(Card::long2board(private_hand),Card::long2board(public_board));
}

namespace {
struct ChooseTable {
  size_t c[53][6]{};
  ChooseTable() {
    for (int n = 0; n <= 52; ++n) {
      c[n][0] = 1;
      for (int k = 1; k <= 5; ++k)
        if (n)
          c[n][k] = c[n - 1][k] + c[n - 1][k - 1];
    }
  }
};
const ChooseTable choose;
} // namespace
size_t Dic5Compairer::denseIndex(uint64_t mask) {
  size_t index = 0;
  int k = 1;
  while (mask) {
    int card = __builtin_ctzll(mask);
    index += choose.c[card][k++];
    mask &= mask - 1;
  }
  return index;
}
int Dic5Compairer::denseRank(uint64_t mask) const {
  int cards[7], n = 0;
  while (mask) {
    if (n == 7)
      throw runtime_error("Too many evaluator cards");
    cards[n++] = __builtin_ctzll(mask);
    mask &= mask - 1;
  }
  if (n < 5)
    throw runtime_error("Too few evaluator cards");
  int best = INT_MAX;
  for (int a = 0; a < n - 4; ++a)
    for (int b = a + 1; b < n - 3; ++b)
      for (int c = b + 1; c < n - 2; ++c)
        for (int d = c + 1; d < n - 1; ++d)
          for (int e = d + 1; e < n; ++e) {
            size_t index = choose.c[cards[a]][1] + choose.c[cards[b]][2] +
                           choose.c[cards[c]][3] + choose.c[cards[d]][4] +
                           choose.c[cards[e]][5];
            auto rank = denseRanks[index];
            if (rank == UINT16_MAX)
              throw runtime_error("Evaluator hand missing from dictionary");
            best = min(best, int(rank));
          }
  return best;
}

void Dic5Compairer::validateDictionary(const string &path, int lines) {
  auto saved = sui::options;
  sui::options.dense = false;
  Dic5Compairer old(path, lines);
  sui::options.dense = true;
  Dic5Compairer packed(path, lines);
  for (const auto &entry : old.cardslong2rank)
    if (packed.denseRank(entry.first) != entry.second)
      throw runtime_error("Five-card evaluator mismatch");
  vector<int> cards;
  for (int i = (lines == 376993 ? 16 : 0); i < 52; ++i)
    cards.push_back(i);
  std::mt19937 generator(20261111);
  for (int trial = 0; trial < 10000; ++trial) {
    std::shuffle(cards.begin(), cards.end(), generator);
    uint64_t mask = 0;
    for (int k = 0; k < 7; ++k)
      mask |= uint64_t(1) << cards[k];
    int rank = INT_MAX;
    for (int a = 0; a < 3; ++a)
      for (int b = a + 1; b < 4; ++b)
        for (int c = b + 1; c < 5; ++c)
          for (int d = c + 1; d < 6; ++d)
            for (int e = d + 1; e < 7; ++e) {
              auto key = (uint64_t(1) << cards[a]) | (uint64_t(1) << cards[b]) |
                         (uint64_t(1) << cards[c]) | (uint64_t(1) << cards[d]) |
                         (uint64_t(1) << cards[e]);
              rank = min(rank, old.cardslong2rank.at(key));
            }
    if (packed.denseRank(mask) != rank)
      throw runtime_error("Seven-card evaluator mismatch");
  }
  sui::options = saved;
  cout << "SUI_EVALUATOR_VALIDATED: five=" << old.cardslong2rank.size()
       << " seven=10000" << endl;
}
