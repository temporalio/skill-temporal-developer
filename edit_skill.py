import io,sys
p = "SKILL.md"
with open(p, "r", encoding="utf-8") as f:
    s = f.read()
needle = "- **`references/core/standalone-activities.md`** - Standalone Activities: run an Activity directly from a Client without a Workflow (Public Preview)\n  - Language-specific info at `references/{your_language}/standalone-activities.md`\n"
insert = (
    "- **`references/core/standalone-activities-renames.md`** - Standalone Activities API renames: summary/details tokens and deprecations\n"
    "  - Language-specific info at `references/{your_language}/standalone-activities-renames.md`\n"
)
if needle in s and insert not in s:
    s = s.replace(needle, needle + insert)
with open(p, "w", encoding="utf-8") as f:
    f.write(s)
print("OK")
