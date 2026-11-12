#pragma once
#include "tools/SuiOptions.h"
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <stdexcept>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>
// File-backed experiment, not a strict resident-memory cap. OS owns page
// eviction. Files are unlinked immediately: normal exit/cancel leaves no
// backing artifacts.
template <class T> class StateBuffer {
  std::vector<T> memory;
  T *mapping = nullptr;
  size_t length = 0;

public:
  StateBuffer() = default;
  StateBuffer(const StateBuffer &) = delete;
  StateBuffer &operator=(const StateBuffer &) = delete;
  ~StateBuffer() {
    if (mapping)
      munmap(mapping, length * sizeof(T));
  }
  void resize(size_t n) {
    if (mapping || !memory.empty())
      throw std::runtime_error("State buffer resized twice");
    length = n;
    if (!n)
      return;
    if (!sui::mappedState) {
      memory.resize(n);
      return;
    }
    std::string directory = sui::stateDirectory;
    if (directory.empty()) {
      const char *t = getenv("TMPDIR");
      directory = t ? t : "/tmp";
    }
    std::string pattern = directory + "/sui-state-XXXXXX";
    std::vector<char> name(pattern.begin(), pattern.end());
    name.push_back(0);
    int fd = mkstemp(name.data());
    if (fd < 0)
      throw std::runtime_error("Cannot create mapped state: " +
                               std::string(strerror(errno)));
    unlink(name.data());
    if (ftruncate(fd, n * sizeof(T))) {
      close(fd);
      throw std::runtime_error("Cannot size mapped state");
    }
    void *p =
        mmap(nullptr, n * sizeof(T), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (p == MAP_FAILED)
      throw std::runtime_error("Cannot map solver state");
    mapping = static_cast<T *>(p);
  }
  size_t size() const { return length; }
  T *data() { return mapping ? mapping : memory.data(); }
  const T *data() const { return mapping ? mapping : memory.data(); }
  T &operator[](size_t n) { return data()[n]; }
  const T &operator[](size_t n) const { return data()[n]; }
};
