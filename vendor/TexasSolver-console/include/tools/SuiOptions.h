#pragma once
#include <algorithm>
#include <string>
#include <vector>
// Configured once before constructing a solver; immutable during parallel
// traversal.
namespace sui {
struct Options {
  bool stack = false, scalar = false, masks = false, dispatch = false,
       coefficients = false;
  bool arena = false, borrowState = false, canonicalSlabs = false;
  bool brCopy = false, stream = false, dense = false, cache = false,
       compactCache = false;
  bool slab = false, blocked = false, halfAverage = false, halfRegret = false;
  bool weakParent = false, lazyBr = false, adaptive = false, phases = false;
};
extern Options options;
extern std::string checkpointPath, resumePath, stateDirectory;
extern bool mappedState, recomputeCache;
extern int checkpointEvery;
void phase(const char *label, unsigned long long started);
unsigned long long now();
void configure(const std::string &specification);
std::string configuration();
// Preserves the old heap path for ablation; fixed scratch is never recursively
// shared.
class CardSums {
  float local[52];
  std::vector<float> heap;

public:
  explicit CardSums(bool stack) : heap(stack ? 0 : 52) {
    if (stack)
      std::fill(local, local + 52, 0.0f);
  }
  float *data() { return heap.empty() ? local : heap.data(); }
  float &operator[](size_t i) { return data()[i]; }
  float *begin() { return data(); }
  float *end() { return data() + 52; }
  size_t size() const { return 52; }
};
} // namespace sui

namespace sui {
// Each recursive frame owns its leased vector. Idle buffers are bounded per
// worker.
template <class T> class Scratch {
  struct Pool {
    std::vector<std::vector<T>> buffers;
    size_t bytes = 0;
  };
  static Pool &pool() {
    thread_local Pool p;
    return p;
  }

public:
  std::vector<T> value;
  explicit Scratch(size_t n) {
    bool reused = false;
    if (options.arena) {
      auto &p = pool();
      if (!p.buffers.empty()) {
        reused = true;
        value = std::move(p.buffers.back());
        p.buffers.pop_back();
        p.bytes -= value.capacity() * sizeof(T);
      }
    }
    value.resize(n);
    if (reused)
      std::fill(value.begin(), value.end(), T{});
  }
  ~Scratch() {
    if (options.arena) {
      auto &p = pool();
      size_t bytes = value.capacity() * sizeof(T);
      if (p.buffers.size() < 32 && bytes <= 1048576 &&
          p.bytes + bytes <= 4194304) {
        p.bytes += bytes;
        p.buffers.push_back(std::move(value));
      }
    }
  }
};
} // namespace sui
