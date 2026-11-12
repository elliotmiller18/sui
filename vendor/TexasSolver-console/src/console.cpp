//
// Created by bytedance on 9.6.21.
//
#include "compairer/Dic5Compairer.h"
#include "tools/CommandLineTool.h"
#include "tools/SuiOptions.h"
#include "tools/argparse.hpp"
#include <cstdlib>

int main(int argc, const char **argv) {
  // Written for Sui by us: report rejected/invalid solves without an abort
  // signal.
  try {
    for (int i = 1; i < argc; ++i)
      if (string(argv[i]) == "--help") {
        cout << "console_solver -i INPUT -r RESOURCES [-m holdem|shortdeck]\n"
             << "  --optimizations baseline|safe|memory|all|FLAG[,no-FLAG]...\n"
             << "  --checkpoint FILE [--checkpoint-every N] --resume FILE\n"
             << "  --state-dir DIR (for the explicit mapped experiment)\n"
             << "  --validate-evaluator holdem|shortdeck\n"
             << "Omit --optimizations for baseline. See "
                "docs/solver-optimization-experiments.md.\n";
        return 0;
      }
    ArgumentParser parser;

    parser.addArgument("-i", "--input_file", 1, true);
    parser.addArgument("-r", "--resource_dir", 1, true);
    parser.addArgument("-m", "--mode", 1, true);

    parser.addArgument("--optimizations", 1, true);
    parser.addArgument("--validate-evaluator", 1, true);
    parser.addArgument("--checkpoint", 1, true);
    parser.addArgument("--checkpoint-every", 1, true);
    parser.addArgument("--resume", 1, true);
    parser.addArgument("--state-dir", 1, true);
    parser.parse(argc, argv);
    auto optimizations = parser.retrieve<string>("optimizations");
    if (optimizations.empty()) {
      if (const char *value = std::getenv("SUI_SOLVER_OPTIMIZATIONS"))
        optimizations = value;
    }
    auto every = parser.retrieve<string>("checkpoint-every");
    if (!every.empty()) {
      size_t used = 0;
      sui::checkpointEvery = stoi(every, &used);
      if (used != every.size() || sui::checkpointEvery < 1)
        throw runtime_error("Invalid checkpoint interval");
    }
    sui::checkpointPath = parser.retrieve<string>("checkpoint");
    if (sui::checkpointEvery && !sui::checkpointPath.size())
      throw runtime_error("--checkpoint-every requires --checkpoint");
    sui::resumePath = parser.retrieve<string>("resume");
    sui::stateDirectory = parser.retrieve<string>("state-dir");
    sui::configure(optimizations.empty() ? "baseline" : optimizations);
    cout << "SUI_OPTIMIZATIONS: " << sui::configuration() << endl;

    string input_file = parser.retrieve<string>("input_file");
    string resource_dir = parser.retrieve<string>("resource_dir");
    if (resource_dir.empty()) {
      resource_dir = "./resources";
    }
    string mode = parser.retrieve<string>("mode");
    if (mode.empty()) {
      mode = "holdem";
    }
    if (mode != "holdem" && mode != "shortdeck")
      throw runtime_error(
          fmt::format("mode {} error, not in ['holdem','shortdeck']", mode));

    auto validate = parser.retrieve<string>("validate-evaluator");
    if (!validate.empty()) {
      if (validate != "holdem" && validate != "shortdeck")
        throw runtime_error("Unknown evaluator validation mode");
      Dic5Compairer::validateDictionary(
          resource_dir + "/compairer/card5_dic_sorted" +
              (validate == "shortdeck" ? "_shortdeck" : "") + ".txt",
          validate == "shortdeck" ? 376993 : 2598961);
      return 0;
    }
    if (input_file.empty()) {
      CommandLineTool clt = CommandLineTool(mode, resource_dir);
      clt.startWorking();
    } else {
      cout << "EXEC FROM FILE" << endl;
      CommandLineTool clt = CommandLineTool(mode, resource_dir);
      clt.execFromFile(input_file);
    }
    return 0;
  } catch (const std::exception &error) {
    cerr << "Solver error: " << error.what() << endl;
    return 1;
  }
}
