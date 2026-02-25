I'm working on building a Skill for developing temporal code. The skill is rooted at plugins/temporal-developer/skills/temporal-developer/.

It is broken down into 4 components:
- SKILL.md: the top-level skill info, getting started
- references/core/: All the language-agnostic documentation
- references/python/: the python specific documentation
- references/typescript/: the typescript specific documentation

Generally, core describes concepts, such as conceptual patterns, common gotchas, etc. The language-specific directories then show concrete examples of those concepts, in the language.

Currently, SKILL.md, core, and python are complete and in a good state. I'm working on the typescript specific documentation now.

**I want you to help me edit references/typescript/patterns.md**. This should be parallel structure to references/core/patterns.md and references/python/patterns.md, but with typescript specific examples.

Right now it already has a lot of content, but it has not yet been reviewed or polished. Please take these steps:
1. Review it, in comparison to references/core/patterns.md and references/python/patterns.md for overall structure and content. Note any gaps that it has relative to those. Also note content it has that is not in Python.
2. Based on that review, in references/typescript/patterns.edits.md, create a list of content that should be added and/or removed. Note that there *may* be some content that is only relevant for TypeScript, and it may thus be appropriate to have it even if it doesn't correspond to Python or core. Conversely, some content in Python may not be applicable to TypeScript.
3. Consult with me on the list of content to add and/or remove.
4. Once we agree on the list, now you should edit references/typescript/patterns.md to add and/or remove the content.
5. Consult with me again. We may loop some here on additional edits.
6. Finally, you will need to do a pass for **correctness** in the content. At this point, you should use the context7 mcp server with /temporalio/sdk-typescript and temporal-docs mcp server to verify correctness of every bit of content.