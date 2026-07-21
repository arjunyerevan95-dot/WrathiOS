// SPDX-License-Identifier: GPL-2.0-only
#include "../../Gate4/WrathDataContract.hpp"

#include <iostream>

int main(int argc, char **argv) {
    if (argc != 2) {
        std::cerr << "usage: wrath-data-contract <installation-or-kp1>\n";
        return 64;
    }

    const auto result = wrath::importer::ValidateInstallation(argv[1]);
    std::cout << "compatible=" << (result.compatible ? 1 : 0) << '\n';
    std::cout << "profile=" << wrath::importer::kCompatibilityProfile << '\n';
    std::cout << "files=" << result.regularFileCount << '\n';
    std::cout << "packages=" << result.packageCount << '\n';
    std::cout << "bytes=" << result.totalBytes << '\n';
    std::cout << "missing=";
    for (std::size_t i = 0; i < result.missingSentinels.size(); ++i) {
        if (i != 0) {
            std::cout << ',';
        }
        std::cout << result.missingSentinels[i];
    }
    std::cout << '\n';
    for (const auto &error : result.errors) {
        std::cout << "error=" << error << '\n';
    }
    for (const auto &warning : result.warnings) {
        std::cout << "warning=" << warning << '\n';
    }
    return result.compatible ? 0 : 2;
}
