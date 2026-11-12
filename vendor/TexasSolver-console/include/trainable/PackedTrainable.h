#pragma once
#include "Deck.h"
#include "StateBuffer.h"
#include "Trainable.h"
#include "ranges/PrivateCards.h"
#include <iostream>
class ActionNode;
// Shared by all betting nodes with the same player and street. Ordered deals
// remain distinct.
struct DealLayout {
  vector<int16_t> rowForDeal;
  vector<vector<uint16_t>> hands;
  vector<size_t> handOffsets;
  size_t rows = 0, totalHands = 0, fullHands = 0;
  DealLayout(const vector<PrivateCards> &range, const vector<Card> &deck,
             uint64_t board, int gap, bool blocked,
             const int (*symmetry)[4] = nullptr);
  size_t handCount(size_t row) const {
    return handOffsets[row + 1] - handOffsets[row];
  }
  size_t hand(size_t row, size_t compact) const {
    return hands.empty() ? compact : hands[row][compact];
  }
};
class PackedStore;
class PackedTrainable final : public Trainable {
  PackedStore *store = nullptr;
  int row = 0;
  friend class PackedStore;

public:
  const vector<float> getAverageStrategy() override;
  const vector<float> getcurrentStrategy() override;
  void updateRegrets(const vector<float> &regrets, int iteration,
                     const vector<float> &reach) override;
  void copyStrategy(shared_ptr<Trainable> other) override;
  json dump_strategy(bool state) override;
  TrainableType get_type() override { return DISCOUNTED_CFR_TRAINABLE; }
};
class PackedStore {
  friend class PackedTrainable;
  ActionNode &node;
  vector<PrivateCards> &range;
  shared_ptr<DealLayout> layout;
  int actions;
  StateBuffer<float> regrets, average;
  StateBuffer<uint16_t> regrets16, average16;
  vector<PackedTrainable> views;
  vector<uint8_t> initialized;
  float read(bool avg, size_t i) const;
  void write(bool avg, size_t i, float value);

public:
  PackedStore(ActionNode &node, vector<PrivateCards> &range,
              shared_ptr<DealLayout> layout);
  PackedTrainable *get(int deal, bool create);
  void checkpoint(std::ostream &out) const;
  void restore(std::istream &in);
};
