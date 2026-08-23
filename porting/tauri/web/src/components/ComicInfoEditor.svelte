<script lang="ts">
  import { getComicinfo, editComicinfo } from '../lib/api';
  import type { ComicInfo } from '../lib/types';

  // Sentinel values mirror the Rust UNSET_INT / UNSET_RATING constants. An unset field
  // comes back as -1 (or -1.0) and is displayed as blank; on save a blank number field
  // goes back as -1, so GenerateComicInfoXML omits it again.
  const UNSET = -1;

  export let open: boolean = false;
  export let filePath: string = '';
  export let onApplied: () => void = () => {};

  type TabId = 'general' | 'story' | 'credits' | 'publishing';

  interface Field {
    key: keyof ComicInfo;
    label: string;
  }

  // Grouped to mirror Lazarus TdlgComicInfoEditor's four-tab layout.
  const GROUPS: Record<TabId, { title: string; fields: Field[] }> = {
    general: {
      title: 'General',
      fields: [
        { key: 'title', label: 'Title' },
        { key: 'series', label: 'Series' },
        { key: 'number', label: 'Number' },
        { key: 'count', label: 'Count' },
        { key: 'volume', label: 'Volume' },
        { key: 'alternate_series', label: 'Alternate Series' },
        { key: 'alternate_number', label: 'Alternate Number' },
        { key: 'alternate_count', label: 'Alternate Count' },
        { key: 'publisher', label: 'Publisher' },
        { key: 'imprint', label: 'Imprint' },
        { key: 'genre', label: 'Genre' },
        { key: 'tags', label: 'Tags' },
        { key: 'web', label: 'Web' },
        { key: 'year', label: 'Year' },
        { key: 'month', label: 'Month' },
        { key: 'day', label: 'Day' },
        { key: 'page_count', label: 'Page Count' },
        { key: 'language_iso', label: 'Language ISO' },
        { key: 'format', label: 'Format' },
        { key: 'age_rating', label: 'Age Rating' },
        { key: 'community_rating', label: 'Community Rating' },
      ],
    },
    story: {
      title: 'Story',
      fields: [
        { key: 'summary', label: 'Summary' },
        { key: 'notes', label: 'Notes' },
        { key: 'characters', label: 'Characters' },
        { key: 'teams', label: 'Teams' },
        { key: 'locations', label: 'Locations' },
        { key: 'story_arc', label: 'Story Arc' },
        { key: 'story_arc_number', label: 'Story Arc Number' },
        { key: 'series_group', label: 'Series Group' },
        { key: 'manga', label: 'Manga' },
        { key: 'black_and_white', label: 'Black & White' },
      ],
    },
    credits: {
      title: 'Credits',
      fields: [
        { key: 'writer', label: 'Writer' },
        { key: 'penciller', label: 'Penciller' },
        { key: 'inker', label: 'Inker' },
        { key: 'colorist', label: 'Colorist' },
        { key: 'letterer', label: 'Letterer' },
        { key: 'cover_artist', label: 'Cover Artist' },
        { key: 'editor', label: 'Editor' },
      ],
    },
    publishing: {
      title: 'Publishing',
      fields: [{ key: 'scan_information', label: 'Scan Information' }],
    },
  };

  const NUMERIC_KEYS = new Set<keyof ComicInfo>([
    'count',
    'volume',
    'alternate_number',
    'alternate_count',
    'year',
    'month',
    'day',
    'page_count',
    'community_rating',
  ]);

  let form: Record<keyof ComicInfo, string> = newFields();
  let activeTab: TabId = 'general';
  let status = ''; // '' | 'saved' | <error>
  let busy = false;

  function newFields(): Record<keyof ComicInfo, string> {
    const f = {} as Record<keyof ComicInfo, string>;
    for (const k of Object.keys(NUMERIC_KEYS)) {
      f[k as keyof ComicInfo] = '';
    }
    return f;
  }

  function toDisplay(n: number | undefined): string {
    if (n === undefined || n === UNSET) return '';
    return String(n);
  }

  // Map a group title ('General'/'Story'/...) to its TabId. Kept in the script so the
  // template never needs an `as` cast (which Svelte's markup parser rejects).
  function toTab(title: string): TabId {
    return title.toLowerCase() as TabId;
  }

  // When the editor opens / its target file changes, load this archive's metadata.
  async function loadMeta() {
    if (!open || !filePath) return;
    status = '';
    form = newFields();
    try {
      const ci = await getComicinfo(filePath);
      if (ci) {
        for (const k of Object.keys(GROUPS.general.fields)) {
          const key = k as keyof ComicInfo;
          if (NUMERIC_KEYS.has(key)) {
            form[key] = toDisplay(Number((ci as unknown as Record<string, unknown>)[key]));
          } else {
            form[key] = String((ci as unknown as Record<string, unknown>)[key] ?? '');
          }
        }
        // Story / credits / publishing fields.
        for (const grp of [GROUPS.story, GROUPS.credits, GROUPS.publishing]) {
          for (const fld of grp.fields) {
            if (NUMERIC_KEYS.has(fld.key)) {
              form[fld.key] = toDisplay(Number((ci as unknown as Record<string, unknown>)[fld.key]));
            } else {
              form[fld.key] = String((ci as unknown as Record<string, unknown>)[fld.key] ?? '');
            }
          }
        }
      }
    } catch (e) {
      status = String(e);
    }
  }

  $: { if (open && filePath) loadMeta(); }

  function apply() {
    const payload = newFields() as unknown as ComicInfo;
    const target = payload as Record<keyof ComicInfo, unknown>;
    for (const k of Object.keys(form) as (keyof ComicInfo)[]) {
      const raw = form[k].trim();
      if (NUMERIC_KEYS.has(k)) {
        target[k] = raw === '' ? UNSET : Number(raw);
      } else {
        target[k] = raw;
      }
    }
    busy = true;
    status = '';
    editComicinfo(filePath, payload)
      .then(() => {
        status = 'saved';
        onApplied();
      })
      .catch((e) => {
        status = String(e);
      })
      .finally(() => {
        busy = false;
      });
  }

  function close() {
    open = false;
    status = '';
  }

</script>

<div class="editor">
  <div class="edit-head">
    <span>Edit ComicInfo metadata</span>
    <button class="link" on:click={close} aria-label="Close editor">Close</button>
  </div>

  <div class="tabs">
    {#each [GROUPS.general, GROUPS.story, GROUPS.credits, GROUPS.publishing] as g}
      <button
        class:active={activeTab === toTab(g.title)}
        on:click={() => { activeTab = toTab(g.title); }}
      >{g.title}</button>
    {/each}
  </div>

  {#if filePath}
    <div class="file">{filePath.split('/').pop()}</div>
  {/if}

  {#each [GROUPS.general, GROUPS.story, GROUPS.credits, GROUPS.publishing] as g}
    {#if (toTab(g.title) === activeTab)}
      <div class="fields">
        {#each g.fields as f}
          {#if f.key === 'summary' || f.key === 'notes' || f.key === 'scan_information'}
            <label class="full">
              {f.label}
              <textarea rows="3" bind:value={form[f.key]} />
            </label>
          {:else}
            <label>
              {f.label}
              <input type="text" bind:value={form[f.key]} />
            </label>
          {/if}
        {/each}
      </div>
    {/if}
  {/each}

  {#if status === 'saved'}
    <p class="good">Saved.</p>
  {:else if status}
    <p class="err">{status}</p>
  {/if}

  <div class="btns">
    <button class="save-btn" on:click={apply} disabled={busy}>Save metadata</button>
    {#if busy}<span class="dim">Saving…</span>{/if}
  </div>
</div>

<style>
  .editor { margin-top: 16px; border-top: 1px solid #eee; padding-top: 10px; }
  .edit-head { display: flex; justify-content: space-between; align-items: center; font-size: 12px; color: #666; margin-bottom: 6px; }
  .link { border: none; background: transparent; color: #2b6cb0; cursor: pointer; padding: 0; font-size: 12px; }
  .tabs { display: flex; gap: 4px; margin-bottom: 8px; flex-wrap: wrap; }
  .tabs button {
    border: 1px solid #ccc; background: #fafafa; color: #555; cursor: pointer;
    padding: 3px 10px; font-size: 11px; border-radius: 3px;
  }
  .tabs button.active { background: #2b6cb0; color: #fff; border-color: #2b6cb0; }
  .file { color: #888; font-size: 11px; margin-bottom: 6px; word-break: break-all; }
  .fields { display: grid; grid-template-columns: 1fr 1fr; gap: 6px 12px; font-size: 12px; }
  .fields label { display: flex; flex-direction: column; gap: 2px; color: #555; }
  .fields label.full { grid-column: 1 / -1; }
  .fields input,
  .fields textarea {
    border: 1px solid #ccc; border-radius: 3px; padding: 4px 6px; font-size: 12px;
    font-family: inherit; width: 100%; box-sizing: border-box;
  }
  .good { color: #38a169; font-size: 12px; margin: 8px 0 0; }
  .err { color: #c53030; font-size: 12px; margin: 8px 0 0; word-break: break-word; }
  .btns { display: flex; align-items: center; gap: 10px; margin-top: 12px; }
  .save-btn { padding: 6px 14px; border: 1px solid #2b6cb0; background: #2b6cb0; color: #fff; border-radius: 4px; cursor: pointer; }
  .save-btn:disabled { opacity: 0.7; }
  .dim { color: #888; font-size: 12px; }
</style>
