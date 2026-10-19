/** Split a SQL migration script without breaking `BEGIN … END;` trigger bodies. */
export function splitSqlStatements(sql: string): string[] {
  const statements: string[] = [];
  let start = 0;
  let index = 0;
  let beginDepth = 0;
  let caseDepth = 0;

  const pushStatement = (end: number): void => {
    const chunk = sql.slice(start, end).trim();
    if (chunk.length > 0) {
      statements.push(chunk);
    }
    start = end;
  };

  while (index < sql.length) {
    const char = sql[index];
    const next = sql[index + 1];
    if (char === "'" || char === '"' || char === "`" || char === "[") {
      const quoteEnd = char === "[" ? "]" : char;
      index += 1;
      while (index < sql.length) {
        if (sql[index] === quoteEnd) {
          if (quoteEnd !== "]" && sql[index + 1] === quoteEnd) {
            index += 2;
            continue;
          }
          index += 1;
          break;
        }
        index += 1;
      }
      continue;
    }
    if (char === "-" && next === "-") {
      index += 2;
      while (index < sql.length && sql[index] !== "\n") index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      index += 2;
      while (
        index < sql.length &&
        !(sql[index] === "*" && sql[index + 1] === "/")
      ) {
        index += 1;
      }
      index = Math.min(sql.length, index + 2);
      continue;
    }
    if (/[A-Za-z_]/.test(char)) {
      const wordStart = index;
      index += 1;
      while (index < sql.length && /[A-Za-z0-9_$]/.test(sql[index])) index += 1;
      const word = sql.slice(wordStart, index).toUpperCase();
      if (word === "BEGIN") beginDepth += 1;
      else if (word === "CASE") caseDepth += 1;
      else if (word === "END") {
        if (caseDepth > 0) caseDepth -= 1;
        else if (beginDepth > 0) {
          beginDepth -= 1;
          if (beginDepth === 0) {
            let end = index;
            while (end < sql.length && /\s/.test(sql[end])) end += 1;
            if (sql[end] === ";") pushStatement(end + 1);
          }
        }
      }
      continue;
    }
    if (char === ";" && beginDepth === 0) {
      index += 1;
      pushStatement(index);
      continue;
    }
    index += 1;
  }

  pushStatement(sql.length);
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
