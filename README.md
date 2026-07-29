# tc4mac Plugin SDK

The contract a [tc4mac](https://tc4mac.com) plugin builds against. It depends
only on Foundation — writing a plugin never means taking on the app's
internals.

```swift
.package(url: "https://github.com/lagueux/tc4mac-plugin-sdk.git", from: "1.0.0")
```

## The four kinds of plugin

tc4mac is a native macOS re-creation of Total Commander, and its plugin
categories mirror Total Commander's — with the *capabilities* carried over,
not the Windows binary interfaces. A `.wcx`, `.wfx`, `.wlx` or `.wdx` DLL
cannot load on macOS; these are the native equivalents.

| Protocol | Equivalent | What it adds to tc4mac |
|---|---|---|
| `FileSystemPlugin` | WFX | A browsable location: cloud storage, a device, anything that lists and reads |
| `PackerPlugin` | WCX | An archive format the panel can enter and, if the format allows, write |
| `ViewerPlugin` | WLX | A file type Lister and Quick View can display |
| `ContentProvider` | WDX | Extra columns, searchable fields, and Multi-Rename placeholders |

One plugin may implement several.

## How a plugin runs

A plugin is an ordinary executable in a `.tcplugin` bundle. tc4mac starts it
in its own process and speaks length-prefixed JSON over its standard input
and output (`PluginWire`), so a crash degrades one feature instead of taking
the app down, and a plugin can be written in any language that can read a
pipe.

The user installs and removes plugins in **Configuration ▸ Plugins**.
Installing is not consenting to run: a plugin starts only once it is also
switched on, and never if its signature cannot be verified.

## Two rules worth knowing before you start

**Declare what you can actually do.** Every plugin type carries a capability
set. tc4mac gates its dialogs on it, so an action you do not declare is never
offered — better than offering it and failing halfway.

**Progress is also cancellation.** `PluginHostServices.report` returns `false`
once the user cancels. A plugin that never reports progress cannot be
interrupted. Call it during any long operation and stop when it says so.

## Samples

- [tc4mac-sample-mht](https://github.com/lagueux/tc4mac-sample-mht) — packer: MHTML saved pages
- [tc4mac-sample-iphone](https://github.com/lagueux/tc4mac-sample-iphone) — file system: browse an iPhone
- [tc4mac-sample-markdown](https://github.com/lagueux/tc4mac-sample-markdown) — viewer: Markdown in Lister
- [tc4mac-sample-imageinfo](https://github.com/lagueux/tc4mac-sample-imageinfo) — content: image properties as columns

## Licence

MIT. See `LICENSE`.
