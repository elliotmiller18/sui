#pragma once
#include "RiverCombs.h"
#include <array>
#include <atomic>
#include <compairer/Compairer.h>
#include <mutex>
#include <unordered_map>
struct CompactRiverComb {
  int rank, reach_prob_index;
};
struct RiverCacheEntry {
  vector<RiverCombs> original;
  vector<CompactRiverComb> compact;
  const vector<PrivateCards> *range = nullptr;
};
struct RiverCombView {
  const RiverCacheEntry *entry;
  shared_ptr<RiverCacheEntry> pin;
  struct Hand {
    int rank;
    const PrivateCards &private_cards;
    int reach_prob_index;
  };
  size_t size() const {
    return entry->range ? entry->compact.size() : entry->original.size();
  }
  Hand operator[](size_t i) const {
    if (entry->range) {
      const auto &c = entry->compact[i];
      return {c.rank, entry->range->at(c.reach_prob_index), c.reach_prob_index};
    }
    const auto &c = entry->original[i];
    return {c.rank, c.private_cards, c.reach_prob_index};
  }
};
class RiverRangeManager {
public:
  RiverRangeManager();
  explicit RiverRangeManager(shared_ptr<Compairer> evaluator);
  void initialize(uint64_t board);
  RiverCombView getRiverCombos(int player, const vector<PrivateCards> &range,
                               const vector<int> &board);
  RiverCombView getRiverCombos(int player, const vector<PrivateCards> &range,
                               uint64_t board);

private:
  struct Slot {
    std::atomic<RiverCacheEntry *> published{nullptr};
    std::mutex lock;
    std::unique_ptr<RiverCacheEntry> owner;
  };
  struct Indexed {
    std::array<Slot, 2758> slots;
  };
  unordered_map<uint64_t, RiverCacheEntry> maps[2];
  shared_ptr<Compairer> handEvaluator;
  shared_ptr<mutex> maplock;
  shared_ptr<Indexed> indexed;
  uint64_t initialBoard = 0;
  RiverCacheEntry build(const vector<PrivateCards> &range, uint64_t board);
};
