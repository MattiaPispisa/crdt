// The region syntax of dart.dev's code excerpter:
// `// #docregion name` … `// #enddocregion name`. Regions may overlap.
const marker = /^\s*\/\/\s*#(docregion|enddocregion)\s+(\S+)\s*$/;
const licenseLine = /^\/\/ (Copyright|SPDX-License-Identifier)/;

function dedent(lines: string[]): string {
  const indents = lines
    .filter((line) => line.trim() !== '')
    .map((line) => line.length - line.trimStart().length);
  const cut = indents.length === 0 ? 0 : Math.min(...indents);
  return lines.map((line) => line.slice(cut)).join('\n');
}

// Every run of blank lines cut to one: a removed marker can leave two blank
// lines next to each other.
function collapseBlankLines(lines: string[]): string[] {
  return lines.filter(
    (line, index) =>
      line.trim() !== '' || index === 0 || lines[index - 1].trim() !== '',
  );
}

function trimBlankLines(lines: string[]): string[] {
  let start = 0;
  let end = lines.length;
  while (start < end && lines[start].trim() === '') start++;
  while (end > start && lines[end - 1].trim() === '') end--;
  return lines.slice(start, end);
}

/** Splits a recipe file into the code to show and its regions. */
export function readRecipeSource(text: string): {
  code: string;
  regions: Record<string, string>;
} {
  const lines = text.replace(/\r\n/g, '\n').split('\n');

  // Every `.dart` file of the repository starts with the license header: it
  // is not part of what a reader copies.
  let start = 0;
  while (start < lines.length && licenseLine.test(lines[start])) start++;

  const code: string[] = [];
  const open = new Map<string, string[]>();
  const regions: Record<string, string> = {};

  for (const line of lines.slice(start)) {
    const match = marker.exec(line);
    if (match) {
      const [, kind, name] = match;
      if (kind === 'docregion') {
        if (open.has(name) || name in regions) {
          throw new Error(`Region "${name}" opens twice.`);
        }
        open.set(name, []);
      } else {
        const body = open.get(name);
        if (!body) {
          throw new Error(`Region "${name}" closes but never opened.`);
        }
        regions[name] = dedent(trimBlankLines(collapseBlankLines(body)));
        open.delete(name);
      }
      continue;
    }
    code.push(line);
    for (const body of open.values()) body.push(line);
  }

  if (open.size > 0) {
    throw new Error(`Region "${[...open.keys()][0]}" never closes.`);
  }
  return { code: trimBlankLines(collapseBlankLines(code)).join('\n'), regions };
}
