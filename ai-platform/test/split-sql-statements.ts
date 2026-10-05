/** Split a SQL migration script without breaking `BEGIN … END;` trigger bodies. */
export function splitSqlStatements(sql: string): string[] {
  const withoutComments = sql.replace(/--[^\n]*\n/g, "\n");
  const statements: string[] = [];
  let start = 0;
  let index = 0;
  let beginDepth = 0;

  const pushStatement = (end: number): void => {
    const chunk = withoutComments.slice(start, end).trim();
    if (chunk.length > 0) {
      statements.push(chunk);
    }
    start = end;
  };

  while (index < withoutComments.length) {
    const remaining = withoutComments.slice(index);
    const beginMatch = remaining.match(/^\s*BEGIN\b/i);
    if (beginMatch) {
      beginDepth += 1;
      index += beginMatch[0].length;
      continue;
    }
    const endMatch = remaining.match(/^\s*END\s*;/i);
    if (endMatch) {
      beginDepth = Math.max(0, beginDepth - 1);
      index += endMatch[0].length;
      if (beginDepth === 0) {
        pushStatement(index);
      }
      continue;
    }
    if (withoutComments[index] === ";" && beginDepth === 0) {
      index += 1;
      pushStatement(index);
      continue;
    }
    index += 1;
  }

  pushStatement(withoutComments.length);
  return statements;
}

export async function applySqlStatements(
  db: D1Database,
  sql: string,
): Promise<void> {
  for (const statement of splitSqlStatements(sql)) {
    await db.prepare(statement).run();
  }
}
