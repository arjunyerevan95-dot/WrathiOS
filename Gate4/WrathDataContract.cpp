// SPDX-License-Identifier: GPL-2.0-only
#include "WrathDataContract.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <fstream>
#include <iomanip>
#include <set>
#include <sstream>
#include <system_error>

namespace wrath::importer {
namespace {

constexpr std::size_t kMaximumArchiveEntries = 200000;
constexpr std::uint64_t kMaximumImportedBytes = 64ULL * 1024ULL * 1024ULL * 1024ULL;
constexpr std::array<const char *, 3> kRequiredSentinels = {
    "progs.dat", "csprogs.dat", "menu.dat"
};

std::string Lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

std::uint16_t ReadLE16(const unsigned char *p) {
    return static_cast<std::uint16_t>(p[0]) |
           (static_cast<std::uint16_t>(p[1]) << 8U);
}

std::uint32_t ReadLE32(const unsigned char *p) {
    return static_cast<std::uint32_t>(p[0]) |
           (static_cast<std::uint32_t>(p[1]) << 8U) |
           (static_cast<std::uint32_t>(p[2]) << 16U) |
           (static_cast<std::uint32_t>(p[3]) << 24U);
}

bool NormalizeVirtualPath(std::string input, std::string &output) {
    std::replace(input.begin(), input.end(), '\\', '/');
    while (input.rfind("./", 0) == 0) {
        input.erase(0, 2);
    }
    if (input.empty() || input.front() == '/' ||
        (input.size() > 1 && input[1] == ':')) {
        return false;
    }

    std::stringstream stream(input);
    std::string component;
    std::vector<std::string> components;
    while (std::getline(stream, component, '/')) {
        if (component.empty() || component == ".") {
            continue;
        }
        if (component == "..") {
            return false;
        }
        components.push_back(component);
    }
    if (components.empty()) {
        return false;
    }

    std::ostringstream normalized;
    for (std::size_t i = 0; i < components.size(); ++i) {
        if (i != 0) {
            normalized << '/';
        }
        normalized << Lower(components[i]);
    }
    output = normalized.str();
    return true;
}

bool ReadExact(std::ifstream &file, char *buffer, std::streamsize count) {
    file.read(buffer, count);
    return file.good() || file.gcount() == count;
}

bool IndexPK3(const std::filesystem::path &path,
              std::set<std::string> &logicalFiles,
              std::vector<std::string> &errors) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        errors.push_back("Could not open PK3 package: " + path.filename().string());
        return false;
    }

    file.seekg(0, std::ios::end);
    const std::streamoff fileSize = file.tellg();
    if (fileSize < 22) {
        errors.push_back("PK3 package is truncated: " + path.filename().string());
        return false;
    }

    const std::streamoff tailSize = std::min<std::streamoff>(fileSize, 65557);
    std::vector<unsigned char> tail(static_cast<std::size_t>(tailSize));
    file.seekg(fileSize - tailSize, std::ios::beg);
    if (!ReadExact(file, reinterpret_cast<char *>(tail.data()), tailSize)) {
        errors.push_back("Could not read PK3 directory: " + path.filename().string());
        return false;
    }

    std::ptrdiff_t eocd = -1;
    for (std::ptrdiff_t i = static_cast<std::ptrdiff_t>(tail.size()) - 22; i >= 0; --i) {
        if (ReadLE32(tail.data() + i) == 0x06054b50U) {
            eocd = i;
            break;
        }
    }
    if (eocd < 0) {
        errors.push_back("PK3 end-of-directory record is missing: " + path.filename().string());
        return false;
    }

    const unsigned char *end = tail.data() + eocd;
    const std::uint16_t disk = ReadLE16(end + 4);
    const std::uint16_t directoryDisk = ReadLE16(end + 6);
    const std::uint16_t entriesOnDisk = ReadLE16(end + 8);
    const std::uint16_t entryCount = ReadLE16(end + 10);
    const std::uint32_t directorySize = ReadLE32(end + 12);
    const std::uint32_t directoryOffset = ReadLE32(end + 16);

    if (disk != 0 || directoryDisk != 0 || entriesOnDisk != entryCount) {
        errors.push_back("Multi-volume PK3 packages are unsupported: " + path.filename().string());
        return false;
    }
    if (entryCount == 0xFFFFU || directoryOffset == 0xFFFFFFFFU || directorySize == 0xFFFFFFFFU) {
        errors.push_back("ZIP64 PK3 packages are unsupported by this importer: " + path.filename().string());
        return false;
    }
    if (entryCount > kMaximumArchiveEntries ||
        static_cast<std::uint64_t>(directoryOffset) + directorySize > static_cast<std::uint64_t>(fileSize)) {
        errors.push_back("PK3 directory is invalid: " + path.filename().string());
        return false;
    }

    file.clear();
    file.seekg(directoryOffset, std::ios::beg);
    for (std::uint32_t index = 0; index < entryCount; ++index) {
        std::array<unsigned char, 46> header{};
        if (!ReadExact(file, reinterpret_cast<char *>(header.data()), header.size()) ||
            ReadLE32(header.data()) != 0x02014b50U) {
            errors.push_back("PK3 central directory is corrupt: " + path.filename().string());
            return false;
        }

        const std::uint16_t flags = ReadLE16(header.data() + 8);
        const std::uint16_t nameLength = ReadLE16(header.data() + 28);
        const std::uint16_t extraLength = ReadLE16(header.data() + 30);
        const std::uint16_t commentLength = ReadLE16(header.data() + 32);
        if ((flags & 0x0001U) != 0U) {
            errors.push_back("Encrypted PK3 entries are unsupported: " + path.filename().string());
            return false;
        }
        if (nameLength == 0) {
            errors.push_back("PK3 contains an unnamed entry: " + path.filename().string());
            return false;
        }

        std::string name(nameLength, '\0');
        if (!ReadExact(file, name.data(), nameLength)) {
            errors.push_back("PK3 entry name is truncated: " + path.filename().string());
            return false;
        }
        file.seekg(static_cast<std::streamoff>(extraLength) + commentLength, std::ios::cur);
        if (!file) {
            errors.push_back("PK3 entry metadata is truncated: " + path.filename().string());
            return false;
        }

        if (!name.empty() && (name.back() == '/' || name.back() == '\\')) {
            continue;
        }
        std::string normalized;
        if (!NormalizeVirtualPath(name, normalized)) {
            errors.push_back("PK3 contains an unsafe path: " + path.filename().string());
            return false;
        }
        logicalFiles.insert(normalized);
    }
    return true;
}

bool IndexPAK(const std::filesystem::path &path,
              std::set<std::string> &logicalFiles,
              std::vector<std::string> &errors) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        errors.push_back("Could not open PAK package: " + path.filename().string());
        return false;
    }

    std::array<unsigned char, 12> header{};
    if (!ReadExact(file, reinterpret_cast<char *>(header.data()), header.size()) ||
        std::string(reinterpret_cast<char *>(header.data()), 4) != "PACK") {
        errors.push_back("PAK header is invalid: " + path.filename().string());
        return false;
    }

    const std::uint32_t directoryOffset = ReadLE32(header.data() + 4);
    const std::uint32_t directoryLength = ReadLE32(header.data() + 8);
    if (directoryLength == 0 || directoryLength % 64U != 0U ||
        directoryLength / 64U > kMaximumArchiveEntries) {
        errors.push_back("PAK directory is invalid: " + path.filename().string());
        return false;
    }

    file.seekg(0, std::ios::end);
    const std::streamoff fileSize = file.tellg();
    if (static_cast<std::uint64_t>(directoryOffset) + directoryLength >
        static_cast<std::uint64_t>(fileSize)) {
        errors.push_back("PAK directory lies outside the file: " + path.filename().string());
        return false;
    }

    file.seekg(directoryOffset, std::ios::beg);
    const std::uint32_t entryCount = directoryLength / 64U;
    for (std::uint32_t index = 0; index < entryCount; ++index) {
        std::array<unsigned char, 64> entry{};
        if (!ReadExact(file, reinterpret_cast<char *>(entry.data()), entry.size())) {
            errors.push_back("PAK directory is truncated: " + path.filename().string());
            return false;
        }
        std::size_t length = 0;
        while (length < 56 && entry[length] != 0) {
            ++length;
        }
        std::string normalized;
        if (length == 0 || !NormalizeVirtualPath(
                std::string(reinterpret_cast<char *>(entry.data()), length), normalized)) {
            errors.push_back("PAK contains an unsafe or empty path: " + path.filename().string());
            return false;
        }
        logicalFiles.insert(normalized);
    }
    return true;
}

std::filesystem::path FindKP1Root(const std::filesystem::path &selected,
                                  std::vector<std::string> &errors) {
    std::error_code error;
    if (!std::filesystem::is_directory(selected, error)) {
        errors.push_back("The selected item is not a directory.");
        return {};
    }
    if (Lower(selected.filename().string()) == "kp1") {
        return selected;
    }

    for (const auto &entry : std::filesystem::directory_iterator(selected, error)) {
        if (error) {
            break;
        }
        if (entry.is_directory(error) && Lower(entry.path().filename().string()) == "kp1") {
            return entry.path();
        }
    }
    errors.push_back("No kp1 directory was found. Select the WRATH installation folder or its kp1 folder.");
    return {};
}

}  // namespace

ValidationResult ValidateInstallation(const std::filesystem::path &selectedPath) {
    ValidationResult result;
    result.kp1Root = FindKP1Root(selectedPath, result.errors);
    if (result.kp1Root.empty()) {
        return result;
    }

    std::set<std::string> logicalFiles;
    std::error_code error;
    const auto options = std::filesystem::directory_options::skip_permission_denied;
    for (std::filesystem::recursive_directory_iterator iterator(result.kp1Root, options, error), end;
         iterator != end; iterator.increment(error)) {
        if (error) {
            result.errors.push_back("The selected directory could not be fully enumerated.");
            break;
        }

        const auto status = iterator->symlink_status(error);
        if (error) {
            result.errors.push_back("A file could not be inspected: " + iterator->path().filename().string());
            break;
        }
        if (std::filesystem::is_symlink(status)) {
            result.errors.push_back("Symbolic links are not accepted in imported game data.");
            continue;
        }
        if (!std::filesystem::is_regular_file(status)) {
            continue;
        }

        ++result.regularFileCount;
        const auto fileSize = iterator->file_size(error);
        if (error) {
            result.errors.push_back("A file size could not be read: " + iterator->path().filename().string());
            break;
        }
        result.totalBytes += fileSize;
        if (result.totalBytes > kMaximumImportedBytes) {
            result.errors.push_back("The selected data exceeds the 64 GiB safety limit.");
            break;
        }

        auto relative = std::filesystem::relative(iterator->path(), result.kp1Root, error);
        if (error) {
            result.errors.push_back("A relative import path could not be resolved.");
            break;
        }
        std::string normalized;
        if (!NormalizeVirtualPath(relative.generic_string(), normalized)) {
            result.errors.push_back("The selected directory contains an unsafe path.");
            continue;
        }
        logicalFiles.insert(normalized);

        const std::string extension = Lower(iterator->path().extension().string());
        if (extension == ".pk3") {
            ++result.packageCount;
            result.packageNames.push_back(relative.generic_string());
            IndexPK3(iterator->path(), logicalFiles, result.errors);
        } else if (extension == ".pak") {
            ++result.packageCount;
            result.packageNames.push_back(relative.generic_string());
            IndexPAK(iterator->path(), logicalFiles, result.errors);
        }
    }

    if (result.regularFileCount == 0) {
        result.errors.push_back("The kp1 directory is empty.");
    }

    for (const char *sentinel : kRequiredSentinels) {
        if (logicalFiles.find(sentinel) == logicalFiles.end()) {
            result.missingSentinels.emplace_back(sentinel);
        }
    }
    if (!result.missingSentinels.empty()) {
        result.errors.push_back("Required WRATH QuakeC outputs are missing.");
    }

    const bool hasMap = std::any_of(logicalFiles.begin(), logicalFiles.end(), [](const std::string &name) {
        return name.rfind("maps/", 0) == 0 && name.size() > 4 && name.ends_with(".bsp");
    });
    if (!hasMap) {
        result.warnings.push_back("No BSP map was visible in loose files or indexed packages.");
    }
    if (result.packageCount == 0) {
        result.warnings.push_back("No PK3 or PAK package was found; only a fully extracted kp1 tree can be used.");
    }

    result.compatible = result.errors.empty() && result.missingSentinels.empty();
    return result;
}

std::string HumanReadableSummary(const ValidationResult &result) {
    std::ostringstream output;
    output << (result.compatible ? "Compatible" : "Not compatible")
           << " with " << kCompatibilityProfile << ". ";
    output << result.regularFileCount << " files, " << result.packageCount << " packages, ";
    output << std::fixed << std::setprecision(1)
           << (static_cast<double>(result.totalBytes) / (1024.0 * 1024.0)) << " MiB.";
    if (!result.missingSentinels.empty()) {
        output << " Missing:";
        for (const auto &sentinel : result.missingSentinels) {
            output << ' ' << sentinel;
        }
        output << '.';
    }
    return output.str();
}

}  // namespace wrath::importer
