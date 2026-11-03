//
// Created by Xuefeng Huang on 2020/1/31.
//

#include "ranges/RiverCombs.h"

RiverCombs::RiverCombs() {

}

RiverCombs::RiverCombs(PrivateCards private_cards, int rank, int reach_prob_index) {
    this->rank = rank;
    this->private_cards = private_cards;
    this->reach_prob_index = reach_prob_index;
}

