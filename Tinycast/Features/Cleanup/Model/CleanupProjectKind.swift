import Foundation

/// A kind of project, found by a marker file, and the build folders it can rebuild.
enum CleanupProjectKind: String, CaseIterable, Sendable {
    case cargo, node, reactNative, rails, unity, stack, cabal, sbt, maven, gradle, cmake, unreal
    case jupyter, python, pythonEnvironment, pixi, composer, pub, elixir, swift, zig, godot, dotnet
    case turborepo, terraform, cocoapods

    var title: String {
        switch self {
        case .cargo: "Cargo"
        case .node: "Node"
        case .reactNative: "React Native"
        case .rails: "Rails"
        case .unity: "Unity"
        case .stack: "Stack"
        case .cabal: "Cabal"
        case .sbt: "SBT"
        case .maven: "Maven"
        case .gradle: "Gradle"
        case .cmake: "CMake"
        case .unreal: "Unreal"
        case .jupyter: "Jupyter"
        case .python: "Python"
        case .pythonEnvironment: "Python environment"
        case .pixi: "Pixi"
        case .composer: "Composer"
        case .pub: "Pub"
        case .elixir: "Elixir"
        case .swift: "Swift"
        case .zig: "Zig"
        case .godot: "Godot"
        case .dotnet: ".NET"
        case .turborepo: "Turborepo"
        case .terraform: "Terraform"
        case .cocoapods: "CocoaPods"
        }
    }

    /// Paths relative to the project folder; `CleanupArtifactRule(tableName:)` reads `dir/*.ext`.
    var artifacts: [String] {
        switch self {
        case .cargo: ["target", ".xwin-cache"]
        case .node: ["node_modules", ".angular"]
        case .reactNative:
            [
                "node_modules", "android/build", "android/.gradle", "ios/build", "ios/DerivedData",
                "ios/Pods", ".expo", ".metro",
            ]
        case .rails: ["tmp/cache", "log/*.log"]
        case .unity: ["Library", "Temp", "Obj", "Logs", "MemoryCaptures", "Build", "Builds"]
        case .stack: [".stack-work"]
        case .cabal: ["dist-newstyle"]
        case .sbt: ["target", "project/target"]
        case .maven: ["target"]
        case .gradle: ["build", ".gradle"]
        case .cmake: ["build", "cmake-build-debug", "cmake-build-release"]
        case .unreal: ["Binaries", "Build", "Saved", "DerivedDataCache", "Intermediate"]
        case .jupyter: [".ipynb_checkpoints"]
        case .python:
            [
                ".mypy_cache", ".nox", ".pytest_cache", ".ruff_cache", ".tox", ".venv", "__pycache__",
                "__pypackages__",
            ]
        // Found by the walk, not by a marker: the environment folder is the build item.
        case .pythonEnvironment: []
        case .pixi: [".pixi"]
        case .composer: ["vendor"]
        case .pub: ["build", ".dart_tool", "linux/flutter/ephemeral", "windows/flutter/ephemeral"]
        case .elixir: ["_build", ".elixir-tools", ".elixir_ls", ".lexical"]
        case .swift: [".build", ".swiftpm"]
        case .zig: ["zig-cache", ".zig-cache", "zig-out"]
        case .godot: [".godot"]
        case .dotnet: ["bin", "obj"]
        case .turborepo: [".turbo"]
        case .terraform: [".terraform"]
        case .cocoapods: ["Pods"]
        }
    }

    private static let markers: [String: CleanupProjectKind] = [
        "Cargo.toml": .cargo, "package.json": .node, "Assembly-CSharp.csproj": .unity,
        "stack.yaml": .stack, "cabal.project": .cabal, "build.sbt": .sbt, "pom.xml": .maven,
        "build.gradle": .gradle, "build.gradle.kts": .gradle, "CMakeLists.txt": .cmake,
        "composer.json": .composer, "pubspec.yaml": .pub, "pixi.toml": .pixi, "mix.exs": .elixir,
        "Package.swift": .swift, "build.zig": .zig, "project.godot": .godot,
        "turbo.json": .turborepo, ".terraform.lock.hcl": .terraform, "Podfile": .cocoapods,
        "pyproject.toml": .python, "requirements.txt": .python,
    ]

    /// Every kind a folder is, in case order; one folder can be a Rails app and a Node project.
    static func kinds(fileNames: Set<String>, directoryNames: Set<String>) -> [CleanupProjectKind] {
        var found = Set(fileNames.compactMap { markers[$0] })
        for name in fileNames {
            if name.hasSuffix(".uproject") { found.insert(.unreal) }
            if name.hasSuffix(".ipynb") { found.insert(.jupyter) }
            if name.hasSuffix(".py") { found.insert(.python) }
            if name.hasSuffix(".csproj") || name.hasSuffix(".fsproj") { found.insert(.dotnet) }
        }
        // A Godot or Unity project carries a .csproj that is theirs, not a .NET project of its own.
        if found.contains(.godot) || found.contains(.unity) { found.remove(.dotnet) }
        if fileNames.isSuperset(of: ["Gemfile", "config.ru"]), directoryNames.contains("config") {
            found.insert(.rails)
        }
        if found.contains(.node), directoryNames.contains("ios") || directoryNames.contains("android") {
            found.remove(.node)
            found.insert(.reactNative)
        }
        return allCases.filter(found.contains)
    }

    /// The union of the kinds' build folders, first mention first.
    static func artifacts(of kinds: [CleanupProjectKind]) -> [String] {
        var seen = Set<String>()
        return kinds.flatMap(\.artifacts).filter { seen.insert($0).inserted }
    }
}
