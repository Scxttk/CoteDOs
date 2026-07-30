# Reporting a security issue

Please report it privately through GitHub's [security advisories](../../security/advisories/new) rather than as a public issue.

No bounty — this is a menu-bar app I wrote for myself, maintained in my spare time. I'll read it and I'll fix what's real.

Things worth knowing before you report:

- **The app is not sandboxed, on purpose.** It intercepts hardware media keys with a CGEvent tap, taps other processes' audio output through CoreAudio, and reads Safari's window through the Accessibility API. None of that is possible inside a container. "The app isn't sandboxed" is a design decision, not a finding.
- **It makes no network requests.** There is no server, no update check, no analytics. If you find something that talks to a network, that *is* a finding.
- **It writes to your Obsidian vault** when you use Quick Capture, to a folder you pick. Path traversal out of the vault root is refused; if you get a write outside it, that's a finding.
- Permissions it asks for and what they're for are listed in the README.
