// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace wrath::importer {

inline constexpr const char *kCompatibilityProfile = "wrath-1.1.2-qc-layout-v1";
inline constexpr const char *kEngineRevision = "f6862f628d6ddc133a9ef67bc4631b6137809772";
inline constexpr const char *kQCRevision = "bf7f46792ed3ed018a3d30bf6ca773900d816de1";

struct ValidationResult {
    bool compatible = false;
    std::filesystem::path kp1Root;
    std::uint64_t totalBytes = 0;
    std::size_t regularFileCount = 0;
    std::size_t packageCount = 0;
    std::vector<std::string> packageNames;
    std::vector<std::string> missingSentinels;
    std::vector<std::string> errors;
    std::vector<std::string> warnings;
};

/// Inspects a selected WRATH installation root or its kp1 directory.
/// Package contents are indexed without extracting proprietary data.
ValidationResult ValidateInstallation(const std::filesystem::path &selectedPath);

std::string HumanReadableSummary(const ValidationResult &result);

}  // namespace wrath::importer
