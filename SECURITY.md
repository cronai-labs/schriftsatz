# Security

## Reporting

Report vulnerabilities privately to **security@cronai.de**, or through GitHub's
[private vulnerability reporting](https://github.com/cronai-labs/schriftsatz/security/advisories/new).
Please do not open a public issue first. Expect an acknowledgement within a week.

## Threat model

This is a build tool that runs on your machine, over documents you supply.

`bin/schriftsatz` invokes `pandoc` and `xelatex` on the input you give it. **A LaTeX
engine executes code.** A hostile Markdown file — via raw LaTeX blocks, `\input`,
`\write18` if shell-escape is enabled — can read and write files as your user. This is
inherent to the toolchain, not specific to this project, and the same is true of running
`pandoc --pdf-engine=xelatex` directly.

Do not run this over untrusted input without a sandbox. Shell escape is not enabled by
this tool and should not be enabled for untrusted documents.

The Lua filters operate on the pandoc AST and do not execute document content, read the
filesystem or open network connections.

## Not in scope

- LaTeX injection from document content you chose to typeset
- vulnerabilities in pandoc, TeX Live or poppler (report those upstream)
