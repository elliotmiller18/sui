#include "tools/SuiOptions.h"
#include <chrono>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <sys/resource.h>
#include <vector>
namespace sui {
Options options;
std::string checkpointPath, resumePath, stateDirectory;
bool mappedState = false, recomputeCache = false;
int checkpointEvery = 0;
struct Flag {
  const char *name;
  bool Options::*field;
};
static const Flag flags[] = {{"canonical-slabs", &Options::canonicalSlabs},
                             {"borrow-state", &Options::borrowState},
                             {"arena", &Options::arena},
                             {"stack", &Options::stack},
                             {"scalar", &Options::scalar},
                             {"masks", &Options::masks},
                             {"dispatch", &Options::dispatch},
                             {"coefficients", &Options::coefficients},
                             {"br-copy", &Options::brCopy},
                             {"stream", &Options::stream},
                             {"dense", &Options::dense},
                             {"cache", &Options::cache},
                             {"compact-cache", &Options::compactCache},
                             {"slab", &Options::slab},
                             {"blocked", &Options::blocked},
                             {"half-average", &Options::halfAverage},
                             {"half-regret", &Options::halfRegret},
                             {"weak-parent", &Options::weakParent},
                             {"lazy-br", &Options::lazyBr},
                             {"adaptive", &Options::adaptive},
                             {"phases", &Options::phases}};
void configure(const std::string &spec) {
  options = {};
  mappedState = false;
  recomputeCache = false;
  std::stringstream input(spec);
  std::string token;
  while (std::getline(input, token, ',')) {
    bool enabled = true;
    if (token.rfind("no-", 0) == 0) {
      enabled = false;
      token = token.substr(3);
    }
    if (token == "baseline" || token == "none") {
      options = {};
      mappedState = false;
      recomputeCache = false;
      continue;
    }
    if (token == "safe" || token == "memory" || token == "all") {
      for (const auto &f : flags)
        if (f.field != &Options::halfAverage &&
            f.field != &Options::halfRegret && f.field != &Options::adaptive &&
            f.field != &Options::phases)
          options.*(f.field) = enabled;
      // A later preset replaces numerical/check policies. In particular,
      // all,safe must not silently retain reduced-precision arrays.
      options.halfAverage = enabled && token != "safe";
      options.halfRegret = options.adaptive = enabled && token == "all";
      continue;
    }
    if (token == "mapped") {
      mappedState = enabled;
      continue;
    }
    if (token == "recompute-cache") {
      recomputeCache = enabled;
      continue;
    }
    bool found = false;
    for (const auto &f : flags)
      if (token == f.name) {
        options.*(f.field) = enabled;
        found = true;
        break;
      }
    if (!found)
      throw std::runtime_error("Unknown optimization: " + token);
  }
  if (mappedState || !checkpointPath.empty() || !resumePath.empty() ||
      options.blocked || options.halfAverage || options.halfRegret)
    options.slab = true;
}
std::string configuration() {
  std::string s;
  for (const auto &f : flags)
    if (options.*(f.field)) {
      if (!s.empty())
        s += ",";
      s += f.name;
    }
  for (const auto &name :
       {mappedState ? "mapped" : "", recomputeCache ? "recompute-cache" : ""})
    if (*name) {
      if (!s.empty())
        s += ",";
      s += name;
    }
  return s.empty() ? "baseline" : s;
}
} // namespace sui

namespace sui {
unsigned long long now() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
void phase(const char *label, unsigned long long started) {
  if (!options.phases)
    return;
  struct rusage u{};
  getrusage(RUSAGE_SELF, &u);
  std::cout << "SUI_PHASE: " << label
            << " elapsed_ms=" << (now() - started) / 1000.0
            << " maxrss_raw=" << u.ru_maxrss << std::endl;
}
} // namespace sui
