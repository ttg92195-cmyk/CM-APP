"""Swap the two sides of the merge conflict in worklog.md so that
origin/main's older Task 27 detailed entry comes BEFORE HEAD's
continuation + later-task entries. Keep both halves — neither is a
duplicate; they describe the same Task 27 from different angles."""

from pathlib import Path

p = Path('/home/z/my-project/worklog.md')
text = p.read_text(encoding='utf-8')

# Locate the three conflict markers
start = text.index('<<<<<<< HEAD\n')
mid = text.index('\n=======\n', start)
end = text.index('\n>>>>>>> origin/main\n', mid)

head_block = text[start + len('<<<<<<< HEAD\n'):mid]
origin_block = text[mid + len('\n=======\n'):end]

# Reorder: origin first (older original entry), then HEAD (continuation
# + later tasks). Drop the three conflict markers.
new_text = (
    text[:start]
    + origin_block
    + head_block
    + text[end + len('\n>>>>>>> origin/main\n'):]
)

p.write_text(new_text, encoding='utf-8')
print(f"Wrote {len(new_text)} bytes")
print(f"  origin block: {len(origin_block)} chars")
print(f"  head block:   {len(head_block)} chars")

# Verify no markers remain
for marker in ('<<<<<<< HEAD', '=======', '>>>>>>> origin/main'):
    if marker in new_text:
        # `=======` can legitimately appear inside a code block as a
        # separator (e.g. ASCII diagrams). Only flag if it's a true
        # git conflict marker on its own line.
        for line in new_text.splitlines():
            if line.strip() == marker:
                print(f"  WARN: leftover marker line: {marker!r}")
                break
print("Done.")
