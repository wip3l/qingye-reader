// Copyright (c) 2026 qingye-plugin-reader contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "guest_engine.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>
#include <unistd.h>

namespace qyplugin {

namespace {

std::vector<std::string> SplitSegments(const std::string& path)
{
    std::vector<std::string> parts;
    std::string current;
    for (char ch : path) {
        if (ch == '/' || ch == '\\') {
            if (!current.empty()) {
                parts.push_back(current);
                current.clear();
            }
        } else {
            current.push_back(ch);
        }
    }
    if (!current.empty()) {
        parts.push_back(current);
    }
    return parts;
}

bool HasInvalidChars(const std::string& s)
{
    for (unsigned char ch : s) {
        if (ch == '\0' || ch < 0x20) return true;
        if (ch == ':') return true;
    }
    return false;
}

} // namespace

bool NormalizeSafeRelativePath(
    const std::string& baseRelDir,
    const std::string& requestedPath,
    std::string& normalizedRelOut)
{
    if (requestedPath.empty() || HasInvalidChars(requestedPath)) return false;

    std::vector<std::string> stack;
    const bool isRelative = requestedPath[0] == '.';
    if (isRelative && !baseRelDir.empty()) {
        for (const auto& seg : SplitSegments(baseRelDir)) {
            if (seg == "." || seg.empty()) continue;
            if (seg == "..") return false;
            stack.push_back(seg);
        }
    } else if (requestedPath[0] == '/' || requestedPath[0] == '\\') {
        return false;
    }

    for (const auto& seg : SplitSegments(requestedPath)) {
        if (seg.empty() || seg == ".") continue;
        if (seg == "..") {
            if (stack.empty()) return false;
            stack.pop_back();
        } else {
            stack.push_back(seg);
        }
    }

    if (stack.empty()) return false;

    std::string joined;
    for (size_t i = 0; i < stack.size(); ++i) {
        if (i > 0) joined.push_back('/');
        joined += stack[i];
    }
    normalizedRelOut = std::move(joined);
    return true;
}

bool ReadPluginTextFile(
    const std::string& pluginRoot,
    const std::string& safeRelPath,
    std::string& contentOut,
    std::string& errorOut)
{
    std::string cleanRel;
    if (!NormalizeSafeRelativePath("", safeRelPath, cleanRel)) {
        errorOut = "invalid module path: " + safeRelPath;
        return false;
    }

    char rootReal[4096];
    if (!realpath(pluginRoot.c_str(), rootReal)) {
        errorOut = "plugin root does not exist";
        return false;
    }
    std::string canonicalRoot(rootReal);
    if (!canonicalRoot.empty() && canonicalRoot.back() != '/') {
        canonicalRoot.push_back('/');
    }

    std::string candidate = canonicalRoot + cleanRel;
    char fileReal[4096];
    if (!realpath(candidate.c_str(), fileReal)) {
        errorOut = "module file not found: " + cleanRel;
        return false;
    }
    std::string canonicalFile(fileReal);
    if (canonicalFile.compare(0, canonicalRoot.size(), canonicalRoot) != 0) {
        errorOut = "module path escapes plugin sandbox: " + cleanRel;
        return false;
    }

    struct stat st {};
    if (stat(canonicalFile.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) {
        errorOut = "not a regular file: " + cleanRel;
        return false;
    }
    if (static_cast<size_t>(st.st_size) > MAX_MODULE_FILE_BYTES) {
        errorOut = "module file exceeds 8 MiB limit: " + cleanRel;
        return false;
    }

    FILE* fp = std::fopen(canonicalFile.c_str(), "rb");
    if (!fp) {
        errorOut = "cannot open module file: " + cleanRel;
        return false;
    }
    contentOut.resize(static_cast<size_t>(st.st_size));
    if (st.st_size > 0) {
        size_t readBytes = std::fread(&contentOut[0], 1, contentOut.size(), fp);
        if (readBytes != contentOut.size()) {
            std::fclose(fp);
            errorOut = "short read on module file: " + cleanRel;
            return false;
        }
    }
    std::fclose(fp);
    return true;
}

} // namespace qyplugin
