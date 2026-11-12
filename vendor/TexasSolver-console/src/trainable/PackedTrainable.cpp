#include "trainable/PackedTrainable.h"
#include "nodes/ActionNode.h"
#include "tools/SuiOptions.h"
#include <cmath>
#include <cstring>
#include <limits>
DealLayout::DealLayout(const vector<PrivateCards> &range,
                       const vector<Card> &deck, uint64_t board, int gap,
                       bool blocked, const int (*symmetry)[4]) {
  const int n = deck.size();
  fullHands = range.size();
  rowForDeal.assign(gap == 2 ? n * n + n + 1 : gap == 1 ? n + 1 : 1, -1);
  handOffsets.push_back(0);
  auto add = [&](int deal, uint64_t mask) {
    rowForDeal.at(deal) = rows++;
    if (blocked) {
      hands.emplace_back();
      for (size_t h = 0; h < range.size(); ++h)
        if (!(range[h].toBoardLong() & mask))
          hands.back().push_back(h);
      totalHands += hands.back().size();
    } else
      totalHands += range.size();
    handOffsets.push_back(totalHands);
  };
  if (!gap)
    add(0, board);
  for (int a = 0; gap && a < n; ++a) {
    auto first = uint64_t(1) << const_cast<Card &>(deck[a]).getCardInt();
    if (first & board)
      continue;
    if (symmetry &&
        symmetry[0][const_cast<Card &>(deck[a]).getCardInt() % 4] < 0)
      continue;
    if (gap == 1)
      add(a + 1, board | first);
    else
      for (int b = 0; b < n; ++b) {
        auto second = uint64_t(1) << const_cast<Card &>(deck[b]).getCardInt();
        if (second & (board | first))
          continue;
        if (symmetry &&
            symmetry[a + 1][const_cast<Card &>(deck[b]).getCardInt() % 4] < 0)
          continue;
        add(1 + n + n * a + b, board | first | second);
      }
  }
}
namespace {
uint16_t encode(float f) {
  if (!std::isfinite(f))
    throw runtime_error("Non-finite packed strategy state");
  uint32_t bits;
  memcpy(&bits, &f, 4);
  bits += 0x7fff + ((bits >> 16) & 1);
  return uint16_t(bits >> 16);
}
float decode(uint16_t value) {
  uint32_t bits = uint32_t(value) << 16;
  float f;
  memcpy(&f, &bits, 4);
  return f;
}
} // namespace
PackedStore::PackedStore(ActionNode &n, vector<PrivateCards> &r,
                         shared_ptr<DealLayout> l)
    : node(n), range(r), layout(std::move(l)), actions(n.getActions().size()),
      views(layout->rows), initialized(layout->rows, 0) {
  const auto count = layout->totalHands * actions;
  if (sui::options.halfRegret)
    regrets16.resize(count);
  else
    regrets.resize(count);
  if (sui::options.halfAverage)
    average16.resize(count);
  else
    average.resize(count);
  for (int i = 0; i < views.size(); ++i) {
    views[i].store = this;
    views[i].row = i;
  }
}
PackedTrainable *PackedStore::get(int deal, bool create) {
  if (deal < 0 || deal >= layout->rowForDeal.size())
    throw runtime_error("Packed deal out of bounds");
  int row = layout->rowForDeal[deal];
  if (row < 0)
    return nullptr;
  if (create)
    initialized[row] = 1;
  return initialized[row] ? &views[row] : nullptr;
}
float PackedStore::read(bool avg, size_t i) const {
  return avg ? (sui::options.halfAverage ? decode(average16[i]) : average[i])
             : (sui::options.halfRegret ? decode(regrets16[i]) : regrets[i]);
}
void PackedStore::write(bool avg, size_t i, float value) {
  if (avg) {
    if (sui::options.halfAverage)
      average16[i] = encode(value);
    else
      average[i] = value;
  } else {
    if (sui::options.halfRegret)
      regrets16[i] = encode(value);
    else
      regrets[i] = value;
  }
}
const vector<float> PackedTrainable::getAverageStrategy() {
  auto &s = *store;
  auto &l = *s.layout;
  const auto count = l.handCount(row), base = l.handOffsets[row] * s.actions;
  vector<float> result(s.actions * l.fullHands, 1.0 / s.actions);
  for (size_t h = 0; h < count; ++h) {
    float sum = 0;
    for (int a = 0; a < s.actions; ++a)
      sum += s.read(true, base + a * count + h);
    for (int a = 0; a < s.actions; ++a)
      result[a * l.fullHands + l.hand(row, h)] =
          sum ? s.read(true, base + a * count + h) / sum : 1.0 / s.actions;
  }
  return result;
}
const vector<float> PackedTrainable::getcurrentStrategy() {
  auto &s = *store;
  auto &l = *s.layout;
  const auto count = l.handCount(row), base = l.handOffsets[row] * s.actions;
  vector<float> result(s.actions * l.fullHands, 1.0 / s.actions);
  for (size_t h = 0; h < count; ++h) {
    float sum = 0;
    for (int a = 0; a < s.actions; ++a)
      sum += max(0.0f, s.read(false, base + a * count + h));
    for (int a = 0; a < s.actions; ++a)
      result[a * l.fullHands + l.hand(row, h)] =
          sum ? max(0.0f, s.read(false, base + a * count + h)) / sum
              : 1.0 / s.actions;
  }
  return result;
}
void PackedTrainable::updateRegrets(const vector<float> &values, int iteration,
                                    const vector<float> &) {
  auto &s = *store;
  auto &l = *s.layout;
  const auto count = l.handCount(row), base = l.handOffsets[row] * s.actions;
  double alpha;
  float coefficient;
  if (sui::options.coefficients) {
    thread_local int previous = -1;
    thread_local double cachedAlpha;
    thread_local float cachedCoefficient;
    if (previous != iteration) {
      auto a = pow(iteration, 1.5f);
      cachedAlpha = a / (1 + a);
      cachedCoefficient = pow(float(iteration) / (iteration + 1), 2.0f);
      previous = iteration;
    }
    alpha = cachedAlpha;
    coefficient = cachedCoefficient;
  } else {
    auto a = pow(iteration, 1.5f);
    alpha = a / (1 + a);
    coefficient = pow(float(iteration) / (iteration + 1), 2.0f);
  }
  for (size_t h = 0; h < count; ++h) {
    float sum = 0;
    for (int a = 0; a < s.actions; ++a) {
      auto index = base + a * count + h;
      float v = values[a * l.fullHands + l.hand(row, h)] + s.read(false, index);
      if (v > 0)
        v *= alpha;
      else
        v *= 0.5f;
      s.write(false, index, v);
      sum += max(0.0f, s.read(false, index));
    }
    for (int a = 0; a < s.actions; ++a) {
      auto index = base + a * count + h;
      float c = s.read(true, index);
      c *= 0.9f;
      const float p =
          sum ? max(0.0f, s.read(false, index)) / sum : 1.0 / s.actions;
      c += p * coefficient;
      s.write(true, index, c);
    }
  }
}
void PackedTrainable::copyStrategy(shared_ptr<Trainable> other) {
  auto from = dynamic_pointer_cast<PackedTrainable>(other);
  if (!from)
    throw runtime_error("Mismatched trainable representation");
  auto &s = *store;
  auto &t = *from->store;
  auto &l = *s.layout;
  const auto count = l.handCount(row), base = l.handOffsets[row] * s.actions;
  // Warmup copies rank-equivalent deals. Map by original hand, never compact
  // index.
  auto &fl = *t.layout;
  auto fc = fl.handCount(from->row), fb = fl.handOffsets[from->row] * t.actions;
  vector<int> source(l.fullHands, -1);
  for (size_t h = 0; h < fc; ++h)
    source[fl.hand(from->row, h)] = h;
  for (size_t h = 0; h < count; ++h)
    for (int a = 0; a < s.actions; ++a) {
      int sh = source[l.hand(row, h)];
      for (bool avg : {false, true})
        s.write(avg, base + a * count + h,
                sh < 0 ? 0 : t.read(avg, fb + a * fc + sh));
    }
}
json PackedTrainable::dump_strategy(bool withState) {
  if (withState)
    throw runtime_error(
        "Use a solver checkpoint, not strategy export, for state");
  auto &s = *store;
  auto probabilities = getAverageStrategy();
  json result;
  vector<string> actions;
  for (auto &a : s.node.getActions())
    actions.push_back(a.toString());
  result["actions"] = actions;
  for (int h = 0; h < s.range.size(); ++h) {
    vector<float> hand(s.actions);
    for (int a = 0; a < s.actions; ++a)
      hand[a] = probabilities[a * s.range.size() + h];
    result["strategy"][s.range[h].toString()] = hand;
  }
  return result;
}
namespace {
uint64_t checksum(const void *data, size_t bytes) {
  const auto *p = static_cast<const unsigned char *>(data);
  uint64_t h = 14695981039346656037ULL;
  for (size_t i = 0; i < bytes; ++i) {
    h ^= p[i];
    h *= 1099511628211ULL;
  }
  return h;
}
template <class T>
void saveBuffer(std::ostream &out, const T *data, size_t count) {
  uint64_t bytes = count * sizeof(T), hash = checksum(data, bytes);
  out.write(reinterpret_cast<char *>(&bytes), 8);
  out.write(reinterpret_cast<char *>(&hash), 8);
  out.write(reinterpret_cast<const char *>(data), bytes);
  if (!out)
    throw runtime_error("Checkpoint write failed");
}
template <class T> void loadBuffer(std::istream &in, T *data, size_t count) {
  uint64_t bytes = 0, hash = 0;
  in.read(reinterpret_cast<char *>(&bytes), 8);
  in.read(reinterpret_cast<char *>(&hash), 8);
  if (bytes != count * sizeof(T))
    throw runtime_error("Checkpoint buffer shape mismatch");
  in.read(reinterpret_cast<char *>(data), bytes);
  if (!in || checksum(data, bytes) != hash)
    throw runtime_error("Corrupt checkpoint payload");
}
} // namespace
void PackedStore::checkpoint(std::ostream &out) const {
  saveBuffer(out, regrets.data(), regrets.size());
  saveBuffer(out, average.data(), average.size());
  saveBuffer(out, regrets16.data(), regrets16.size());
  saveBuffer(out, average16.data(), average16.size());
  saveBuffer(out, initialized.data(), initialized.size());
}
void PackedStore::restore(std::istream &in) {
  loadBuffer(in, regrets.data(), regrets.size());
  loadBuffer(in, average.data(), average.size());
  loadBuffer(in, regrets16.data(), regrets16.size());
  loadBuffer(in, average16.data(), average16.size());
  loadBuffer(in, initialized.data(), initialized.size());
  for (auto v : initialized)
    if (v > 1)
      throw runtime_error("Invalid checkpoint state flag");
  if (!regrets.size() && !regrets16.size())
    return;
  for (size_t i = 0; i < layout->totalHands * actions; ++i)
    if (!std::isfinite(read(false, i)) || !std::isfinite(read(true, i)))
      throw runtime_error("Non-finite checkpoint state");
}
