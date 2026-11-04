/** Thin typed helpers over D1 prepared statements. */

export async function first<T>(statement: D1PreparedStatement): Promise<T | null> {
  return await statement.first<T>();
}

export async function all<T>(statement: D1PreparedStatement): Promise<T[]> {
  const result = await statement.all<T>();
  return result.results ?? [];
}

export async function run(statement: D1PreparedStatement): Promise<D1Result> {
  return await statement.run();
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export function placeholders(count: number): string {
  return Array.from({ length: count }, () => '?').join(', ');
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) chunks.push(items.slice(i, i + size));
  return chunks;
}

/** SQLite stores booleans as integers. */
export function toDbBool(value: boolean): number {
  return value ? 1 : 0;
}
