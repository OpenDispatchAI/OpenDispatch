# Contributing to OpenDispatch

## Prerequisites

- Xcode 16+
- iOS 18+ SDK
- [Git LFS](https://git-lfs.github.com/) — required for large model weight files

### Git LFS Setup

This repo uses Git LFS for ML model weights (`.bin` files). Install it before cloning:

```bash
# macOS
brew install git-lfs
git lfs install

# Then clone as usual
git clone <repo-url>
```

If you already cloned without LFS, run:

```bash
git lfs install
git lfs pull
```

Without Git LFS, model weight files will be checked out as small pointer files instead of the actual weights, and the embedding model will fail to load.

## Running Tests

```bash
cd Packages/RouterCore && swift test
cd Packages/SkillRegistry && swift test
cd Packages/SkillCompiler && swift test
```

## Building the App

```bash
xcodebuild -project OpenDispatchApp/OpenDispatch.xcodeproj -scheme OpenDispatch -destination 'generic/platform=iOS Simulator' build
```
