#include "ranges/RiverRangeManager.h"
#include "tools/SuiOptions.h"
#include <algorithm>
RiverRangeManager::RiverRangeManager() = default;
RiverRangeManager::RiverRangeManager(shared_ptr<Compairer> evaluator)
    : handEvaluator(std::move(evaluator)), maplock(std::make_shared<mutex>()) {}
void RiverRangeManager::initialize(uint64_t board) {
  initialBoard = board;
  if (sui::options.cache)
    indexed = std::make_shared<Indexed>();
}
RiverCombView
RiverRangeManager::getRiverCombos(int player, const vector<PrivateCards> &range,
                                  const vector<int> &board) {
  return getRiverCombos(player, range, Card::boardInts2long(board));
}
RiverCacheEntry RiverRangeManager::build(const vector<PrivateCards> &range,
                                         uint64_t board) {
  RiverCacheEntry entry;
  if (sui::options.compactCache) {
    entry.range = &range;
    entry.compact.reserve(range.size());
    for (int i = 0; i < range.size(); ++i)
      if (!(range[i].toBoardLong() & board))
        entry.compact.push_back(
            {handEvaluator->get_rank(range[i].toBoardLong(), board), i});
    std::sort(entry.compact.begin(), entry.compact.end(),
              [](const auto &a, const auto &b) { return a.rank > b.rank; });
  } else {
    int count = 0;
    for (auto hand : range)
      if (!(hand.toBoardLong() & board))
        ++count;
    entry.original.resize(count);
    int index = 0;
    for (int i = 0; i < range.size(); ++i) {
      PrivateCards hand = range[i];
      if (hand.toBoardLong() & board)
        continue;
      int rank = handEvaluator->get_rank(hand.toBoardLong(), board);
      RiverCombs comb(hand, rank, i);
      entry.original[index++] = comb;
    }
    std::sort(entry.original.begin(), entry.original.end(),
              [](const auto &a, const auto &b) { return a.rank > b.rank; });
  }
  return entry;
}
RiverCombView
RiverRangeManager::getRiverCombos(int player, const vector<PrivateCards> &range,
                                  uint64_t board) {
  if (player < 0 || player > 1)
    throw runtime_error("Invalid cache player");
  if (sui::recomputeCache) {
    auto value = std::make_shared<RiverCacheEntry>(build(range, board));
    return {value.get(), value};
  }
  if (sui::options.cache) {
    uint64_t extra = board & ~initialBoard;
    int count = __builtin_popcountll(extra);
    int key = 0;
    if ((board & initialBoard) != initialBoard || count > 2)
      throw runtime_error("Board outside indexed cache");
    if (count == 1)
      key = 1 + __builtin_ctzll(extra);
    if (count == 2) {
      int lo = __builtin_ctzll(extra);
      extra &= extra - 1;
      int hi = __builtin_ctzll(extra);
      key = 53 + hi * (hi - 1) / 2 + lo;
    }
    auto &slot = indexed->slots.at(player * 1379 + key);
    if (auto *p = slot.published.load(std::memory_order_acquire))
      return {p};
    std::lock_guard<std::mutex> guard(slot.lock);
    if (!slot.owner) {
      slot.owner = std::make_unique<RiverCacheEntry>(build(range, board));
      slot.published.store(slot.owner.get(), std::memory_order_release);
    }
    return {slot.owner.get()};
  }
  {
    std::lock_guard<std::mutex> guard(*maplock);
    auto it = maps[player].find(board);
    if (it != maps[player].end())
      return {&it->second};
  }
  auto entry = build(range, board);
  std::lock_guard<std::mutex> guard(*maplock);
  auto result = maps[player].emplace(board, std::move(entry));
  return {&result.first->second};
}
