import { z } from 'zod';
import type { Env } from './types';
import type { Difficulty } from './business/points';
import { DIFFICULTY_POINTS } from './business/points';

/**
 * DeepSeek challenge generation.
 *
 * AI output is untrusted: JSON is parsed defensively, every item is validated
 * with zod, strings are trimmed/clamped, and anything unusable falls back to a
 * built-in, safe challenge pool. A partially valid response is topped up from
 * the pool, so a week always has exactly N challenges.
 */

export interface ChallengeDraft {
  title: string;
  description: string;
  difficulty: Difficulty;
}

export interface GenerateChallengesParams {
  env: Env;
  count: number;
  theme: string | null;
  language: string;
  timezone: string;
  previousTitles: readonly string[];
  fetchImpl?: typeof fetch;
}

export interface GenerateChallengesResult {
  challenges: ChallengeDraft[];
  source: 'deepseek' | 'fallback';
}

const MAX_TITLE = 80;
const MAX_DESCRIPTION = 300;

const clamp = (value: string, max: number): string => value.trim().slice(0, max).trim();

const aiChallengeSchema = z
  .object({
    title: z.string().min(1).max(4000),
    description: z.string().max(8000).optional(),
    difficulty: z.preprocess(
      (value) => (typeof value === 'string' ? value.trim().toLowerCase() : value),
      z.enum(['easy', 'medium', 'hard']),
    ),
  })
  .passthrough();

/**
 * Accepts the parsed JSON body (either `{challenges: [...]}` or a bare array)
 * and returns up to `count` valid, de-duplicated, clamped drafts. Invalid
 * items are discarded. Returns null when the root shape is unusable.
 */
export function parseChallengesPayload(payload: unknown, count: number): ChallengeDraft[] | null {
  let items: unknown[];
  if (Array.isArray(payload)) {
    items = payload;
  } else if (payload && typeof payload === 'object' && Array.isArray((payload as { challenges?: unknown }).challenges)) {
    items = (payload as { challenges: unknown[] }).challenges;
  } else {
    return null;
  }

  const result: ChallengeDraft[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    const parsed = aiChallengeSchema.safeParse(item);
    if (!parsed.success) continue;
    const title = clamp(parsed.data.title, MAX_TITLE);
    if (!title) continue;
    const key = title.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    const description = clamp(parsed.data.description ?? '', MAX_DESCRIPTION) || title;
    result.push({ title, description, difficulty: parsed.data.difficulty });
    if (result.length >= count) break;
  }
  return result;
}

interface PoolChallenge extends ChallengeDraft {}

const FALLBACK_EN: readonly PoolChallenge[] = [
  { title: 'Cook a meal for someone', description: 'Make a home-cooked dish for a friend or family member and photograph the plate together.', difficulty: 'easy' },
  { title: 'Learn a 20-second dance', description: 'Learn a short dance routine and record a video of you performing it.', difficulty: 'easy' },
  { title: 'Draw a friend from memory', description: 'Draw a portrait of a friend without looking at a photo, then show them the result.', difficulty: 'easy' },
  { title: 'Walk 10,000 steps', description: 'Walk 10,000 steps in one day and capture a photo of your step counter.', difficulty: 'medium' },
  { title: 'Build a blanket fort', description: 'Build a blanket fort big enough to sit inside and film yourself hanging out in it.', difficulty: 'easy' },
  { title: 'Try a new food', description: 'Eat a food you have never tried before and film your honest first reaction.', difficulty: 'easy' },
  { title: 'Write a short poem', description: 'Write a four-line poem about your week and read it aloud on video.', difficulty: 'easy' },
  { title: 'Do 50 push-ups', description: 'Complete 50 push-ups in one session and film a short clip as proof.', difficulty: 'medium' },
  { title: 'Call an old friend', description: 'Call someone you have not spoken to in months and take a screenshot of the call log.', difficulty: 'easy' },
  { title: 'Recreate a movie scene', description: 'Recreate a famous movie scene with household objects and record the result.', difficulty: 'medium' },
  { title: 'Make homemade pasta', description: 'Make pasta from scratch and photograph the finished dish.', difficulty: 'medium' },
  { title: 'Learn 10 words in a new language', description: 'Learn ten words in a language you do not speak and record yourself saying them.', difficulty: 'medium' },
  { title: 'Sunrise photo', description: 'Wake up for sunrise and take a photo of the sky from somewhere nearby.', difficulty: 'medium' },
  { title: 'Bake something from scratch', description: 'Bake a dessert or bread from scratch and photograph it before it disappears.', difficulty: 'medium' },
  { title: 'Teach a 60-second skill', description: 'Record a one-minute video teaching the group something you know how to do.', difficulty: 'medium' },
  { title: 'Run 5 kilometres', description: 'Run or walk 5 km continuously and share a photo of your route or watch.', difficulty: 'hard' },
  { title: 'No-phone morning', description: 'Spend the first three hours of a day without your phone and film a recap afterwards.', difficulty: 'hard' },
  { title: 'Cold plunge or cold shower', description: 'Take a cold shower or plunge for at least 60 seconds and record a short reaction clip.', difficulty: 'medium' },
  { title: 'Donate or volunteer', description: 'Donate items or volunteer for an hour, and photograph the organisation or drop-off point.', difficulty: 'hard' },
  { title: 'Write a song verse', description: 'Write and perform one verse of an original song on video.', difficulty: 'hard' },
  { title: 'Host a game night', description: 'Invite friends over for a game night and take a group photo.', difficulty: 'medium' },
  { title: 'Make a time-lapse', description: 'Film a 15-second time-lapse of something changing, such as a drawing or a sunset.', difficulty: 'easy' },
  { title: 'Compliment five people', description: 'Give five genuine compliments in one day and describe the experience on video.', difficulty: 'easy' },
  { title: 'Fix something broken', description: 'Repair an item you were about to throw away and photograph the before and after.', difficulty: 'hard' },
  { title: 'Read 30 pages', description: 'Read thirty pages of a book in one sitting and photograph the page you reached.', difficulty: 'easy' },
  { title: 'Make someone laugh', description: 'Make a friend laugh with an original joke and record their reaction (with permission).', difficulty: 'medium' },
];

const FALLBACK_FR: readonly PoolChallenge[] = [
  { title: 'Cuisine un plat pour quelqu’un', description: 'Prépare un plat maison pour un ami ou ta famille et photographie l’assiette ensemble.', difficulty: 'easy' },
  { title: 'Apprends une danse de 20 secondes', description: 'Apprends une courte chorégraphie et filme-toi en train de la danser.', difficulty: 'easy' },
  { title: 'Dessine un ami de mémoire', description: 'Dessine le portrait d’un ami sans regarder de photo, puis montre-lui le résultat.', difficulty: 'easy' },
  { title: 'Marche 10 000 pas', description: 'Marche 10 000 pas dans la journée et prends une photo de ton compteur.', difficulty: 'medium' },
  { title: 'Construis un fort en couvertures', description: 'Construis un fort en couvertures assez grand pour t’asseoir dedans et filme-toi à l’intérieur.', difficulty: 'easy' },
  { title: 'Goûte un aliment inconnu', description: 'Goûte un aliment que tu n’as jamais mangé et filme ta première réaction.', difficulty: 'easy' },
  { title: 'Écris un petit poème', description: 'Écris un poème de quatre vers sur ta semaine et lis-le à voix haute en vidéo.', difficulty: 'easy' },
  { title: 'Fais 50 pompes', description: 'Réalise 50 pompes en une séance et filme un court extrait comme preuve.', difficulty: 'medium' },
  { title: 'Appelle un vieil ami', description: 'Appelle quelqu’un à qui tu n’as pas parlé depuis des mois et prends une capture de l’appel.', difficulty: 'easy' },
  { title: 'Rejoue une scène de film', description: 'Rejoue une scène célèbre avec des objets du quotidien et filme le résultat.', difficulty: 'medium' },
  { title: 'Fabrique des pâtes maison', description: 'Prépare des pâtes fraîches et photographie le plat terminé.', difficulty: 'medium' },
  { title: 'Apprends 10 mots d’une nouvelle langue', description: 'Apprends dix mots dans une langue que tu ne parles pas et enregistre-toi en les disant.', difficulty: 'medium' },
  { title: 'Photo du lever de soleil', description: 'Lève-toi pour le lever du soleil et prends une photo du ciel près de chez toi.', difficulty: 'medium' },
  { title: 'Cuisine une pâtisserie maison', description: 'Prépare un dessert ou du pain maison et photographie-le avant qu’il ne disparaisse.', difficulty: 'medium' },
  { title: 'Enseigne une compétence en 60 secondes', description: 'Filme une vidéo d’une minute pour apprendre quelque chose au groupe.', difficulty: 'medium' },
  { title: 'Cours 5 kilomètres', description: 'Cours ou marche 5 km sans t’arrêter et partage une photo de ton parcours ou de ta montre.', difficulty: 'hard' },
  { title: 'Matinée sans téléphone', description: 'Passe les trois premières heures de la journée sans téléphone et filme un bilan ensuite.', difficulty: 'hard' },
  { title: 'Douche froide', description: 'Prends une douche froide d’au moins 60 secondes et filme une courte réaction.', difficulty: 'medium' },
  { title: 'Donne ou fais du bénévolat', description: 'Donne des objets ou fais une heure de bénévolat, et photographie le lieu.', difficulty: 'hard' },
  { title: 'Écris un couplet de chanson', description: 'Écris et interprète un couplet d’une chanson originale en vidéo.', difficulty: 'hard' },
  { title: 'Organise une soirée jeux', description: 'Invite des amis pour une soirée jeux et prends une photo de groupe.', difficulty: 'medium' },
  { title: 'Réalise un time-lapse', description: 'Filme un time-lapse de 15 secondes de quelque chose qui change, comme un dessin ou un coucher de soleil.', difficulty: 'easy' },
  { title: 'Fais cinq compliments', description: 'Fais cinq compliments sincères en une journée et raconte l’expérience en vidéo.', difficulty: 'easy' },
  { title: 'Répare un objet cassé', description: 'Répare un objet que tu allais jeter et photographie avant et après.', difficulty: 'hard' },
];

function fallbackPool(language: string): readonly PoolChallenge[] {
  return language.toLowerCase().startsWith('fr') ? FALLBACK_FR : FALLBACK_EN;
}

/** Deterministic, avoids the previous three weeks' titles when possible. */
export function fallbackChallenges(
  count: number,
  language: string,
  previousTitles: readonly string[] = [],
): ChallengeDraft[] {
  const safeCount = Math.max(0, Math.min(10, Math.floor(count)));
  const pool = fallbackPool(language);
  if (safeCount === 0) return [];

  const previous = new Set(previousTitles.map((title) => title.trim().toLowerCase()));
  const offset = (previousTitles.length * 7 + safeCount * 3) % pool.length;
  const rotated = pool.map((_, index) => pool[(index + offset) % pool.length]!);
  const fresh = rotated.filter((challenge) => !previous.has(challenge.title.toLowerCase()));
  const ordered = [...fresh, ...rotated];

  const result: ChallengeDraft[] = [];
  const seen = new Set<string>();
  for (const challenge of ordered) {
    const key = challenge.title.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({ ...challenge });
    if (result.length >= safeCount) break;
  }
  return result;
}

function fillFromFallback(
  drafts: readonly ChallengeDraft[],
  count: number,
  language: string,
  previousTitles: readonly string[],
): ChallengeDraft[] {
  const result = [...drafts];
  const seen = new Set(result.map((draft) => draft.title.toLowerCase()));
  for (const candidate of fallbackChallenges(count + result.length, language, previousTitles)) {
    if (result.length >= count) break;
    const key = candidate.title.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(candidate);
  }
  // Extremely defensive: if the pool was exhausted, repeat a fallback item.
  const pool = fallbackPool(language);
  let index = 0;
  while (result.length < count) {
    const candidate = pool[index % pool.length]!;
    result.push({ ...candidate });
    index += 1;
  }
  return result.slice(0, count);
}

function languageName(language: string): string {
  return language.toLowerCase().startsWith('fr') ? 'French' : 'English';
}

export function buildChallengePrompt(params: {
  count: number;
  theme: string | null;
  language: string;
  timezone: string;
  previousTitles: readonly string[];
}): string {
  const previous = params.previousTitles.length
    ? params.previousTitles.map((title) => `- ${title}`).join('\n')
    : '- (none yet)';
  return [
    `Create exactly ${params.count} weekly dares for a small friend group.`,
    `Write all titles and descriptions in ${languageName(params.language)}.`,
    `Group timezone: ${params.timezone}.`,
    params.theme ? `Theme: ${params.theme}` : 'Theme: surprise us, keep it varied.',
    '',
    'Rules:',
    '- Dares must be safe, legal, non-humiliating, and doable within one week.',
    '- They must be provable with a photo or a short video.',
    '- Do not require spending a lot of money, alcohol, or anything risky.',
    '- Mix easy, medium and hard difficulty.',
    '- Each title is at most 80 characters; each description is at most 300 characters.',
    '- Avoid repeating these titles from the previous three weeks:',
    previous,
    '',
    'Respond with JSON only, using exactly this shape:',
    '{"challenges":[{"title":"...","description":"...","difficulty":"easy|medium|hard"}]}',
  ].join('\n');
}

const deepseekResponseSchema = z
  .object({
    choices: z
      .array(
        z
          .object({
            message: z.object({ content: z.string() }).passthrough(),
          })
          .passthrough(),
      )
      .min(1),
  })
  .passthrough();

function stripCodeFence(content: string): string {
  const trimmed = content.trim();
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed);
  return fenced?.[1]?.trim() ?? trimmed;
}

export async function generateChallenges(
  params: GenerateChallengesParams,
): Promise<GenerateChallengesResult> {
  const fallback = (): GenerateChallengesResult => ({
    challenges: fallbackChallenges(params.count, params.language, params.previousTitles),
    source: 'fallback',
  });

  const apiKey = params.env.DEEPSEEK_API_KEY?.trim();
  if (!apiKey) return fallback();

  const baseUrl = (params.env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com').replace(/\/+$/u, '');
  const fetchImpl = params.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);

  try {
    const response = await fetchImpl(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${apiKey}`,
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
        response_format: { type: 'json_object' },
        temperature: 0.9,
        messages: [
          {
            role: 'system',
            content:
              'You design safe, playful, camera-provable weekly challenges for friend groups. Reply with valid JSON only.',
          },
          {
            role: 'user',
            content: buildChallengePrompt(params),
          },
        ],
      }),
      signal: controller.signal,
    });

    if (!response.ok) return fallback();

    const raw: unknown = await response.json();
    const envelope = deepseekResponseSchema.safeParse(raw);
    if (!envelope.success) return fallback();

    let payload: unknown;
    try {
      payload = JSON.parse(stripCodeFence(envelope.data.choices[0]!.message.content));
    } catch {
      return fallback();
    }

    const valid = parseChallengesPayload(payload, params.count);
    if (!valid || valid.length === 0) return fallback();

    if (valid.length < params.count) {
      return {
        challenges: fillFromFallback(valid, params.count, params.language, params.previousTitles),
        source: 'deepseek',
      };
    }
    return { challenges: valid.slice(0, params.count), source: 'deepseek' };
  } catch {
    return fallback();
  } finally {
    clearTimeout(timeout);
  }
}

/** Kept next to the pool so callers can render difficulty points consistently. */
export function pointsForDraft(draft: ChallengeDraft): number {
  return DIFFICULTY_POINTS[draft.difficulty];
}
