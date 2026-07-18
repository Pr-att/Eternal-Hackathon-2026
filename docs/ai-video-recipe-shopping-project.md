# AI Video Recipe Shopping — Project Spec & Build Plan

**One-liner:** Share a cooking video (YouTube/Instagram/TikTok) to Blinkit. AI watches/reads it, figures out what ingredients you'll actually need to *buy* (not equipment you already own, not staples like salt), matches them to real SKUs at the right pack size, and hands you a ready-to-edit cart.

---

## 1. Problem Statement

People watch cooking videos and want to cook the dish *now*, but today that means: pause the video repeatedly, manually write down ingredients, open a grocery app, search each item one by one, guess pack sizes, and hope nothing's missed. This kills the impulse — most people just don't cook the recipe.

**What we're building:** collapse that entire flow into one share-sheet tap.

## 2. Goals / Non-Goals

**Goals**
- From a shared video URL, produce an accurate, correctly-scoped grocery cart in under ~15 seconds.
- Correctly distinguish *consumables* (buy) vs *equipment* (own already, suggest only) vs *staples* (skip, assume owned).
- Match extracted ingredients to real Blinkit SKUs with sensible pack sizes and substitutions.
- Let the user edit the cart before checkout — AI proposes, user disposes.

**Non-goals (v1)**
- Not trying to transcribe/understand *every* video perfectly — graceful degradation (partial cart + "we couldn't catch everything, review below") is acceptable.
- Not building a general video-understanding platform — scope is strictly recipe/cooking content.
- Not handling multi-recipe videos (e.g. "5 breakfast ideas") in v1 — single-recipe videos only.

## 3. High-Level Architecture

```
┌─────────────┐     share sheet      ┌──────────────────────┐
│  YouTube /   │ ───────────────────▶ │  iOS Share Extension  │
│  Instagram   │      video URL       │  (or Blinkit app tab) │
└─────────────┘                       └──────────┬────────────┘
                                                  │ POST /extract
                                                  ▼
                                   ┌───────────────────────────────┐
                                   │      Ingestion Service         │
                                   │  - fetch video/metadata        │
                                   │  - pull captions/transcript    │
                                   │    if available                │
                                   │  - else: audio → speech-to-text│
                                   │  - sample key frames (vision)  │
                                   └──────────────┬─────────────────┘
                                                  │ raw transcript + frames
                                                  ▼
                                   ┌───────────────────────────────┐
                                   │   Extraction & Classification  │
                                   │   (LLM w/ vision+text input)   │
                                   │  - list items mentioned        │
                                   │  - classify: consumable /      │
                                   │    equipment / staple          │
                                   │  - estimate quantities         │
                                   └──────────────┬─────────────────┘
                                                  │ structured ingredient list
                                                  ▼
                                   ┌───────────────────────────────┐
                                   │      SKU Matching Service      │
                                   │  - embed ingredient names      │
                                   │  - vector search vs catalog    │
                                   │  - pack-size heuristic         │
                                   │  - suppress items user already │
                                   │    owns (purchase history)     │
                                   └──────────────┬─────────────────┘
                                                  │ cart draft
                                                  ▼
                                   ┌───────────────────────────────┐
                                   │        Cart Builder API        │
                                   │  - create draft Blinkit cart   │
                                   │  - return editable line items  │
                                   └──────────────┬─────────────────┘
                                                  │
                                                  ▼
                                        User reviews & checks out
                                        (existing Blinkit checkout)
```

## 4. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Mobile entry point | iOS Share Extension (SwiftUI) + Android Share Intent | Native share-sheet is the whole UX hook |
| Backend orchestration | FastAPI (Python) | Fast to iterate, great ecosystem for AI/video libs |
| Async job queue | Celery + Redis (or a lightweight SQS-style queue) | Video processing is not instant; needs background jobs + polling/websocket for the client |
| Video/caption fetch | `yt-dlp` for metadata + captions where available | Avoids full video download when captions exist |
| Speech-to-text (fallback) | Whisper (self-hosted or API) | Needed when no captions exist |
| Frame sampling | `ffmpeg` to extract 1 frame every N seconds | Cheap way to get visual context without full video understanding |
| Extraction / classification | Claude (vision + text) via API | Single call can take transcript + sampled frames and return structured JSON |
| SKU matching | Embeddings (e.g. `text-embedding-3-small`-equivalent) + pgvector | Fast approximate matching of "turmeric" → catalog SKU |
| Database | Postgres (Supabase for hackathon speed) | Relational data (users, carts, catalog) + pgvector in one place |
| Purchase history signal | Query existing Blinkit order history service (mocked in MVP) | Suppresses equipment suggestions the user already owns |
| Cart/checkout | Existing Blinkit cart API (mocked in MVP) | Don't rebuild checkout — just produce a valid cart payload |

## 5. Data Model (simplified)

```
Video
  id, source_url, platform, transcript_text, has_captions, processed_at

ExtractedItem
  id, video_id, raw_name, category [consumable|equipment|staple],
  estimated_quantity, unit, confidence

SkuMatch
  id, extracted_item_id, sku_id, pack_size, match_confidence, matched_by [exact|embedding|manual]

CartDraft
  id, video_id, user_id, status [draft|edited|checked_out], created_at

CartLineItem
  id, cart_draft_id, sku_id, quantity, source [auto|user_added|user_edited], suppressed_reason (nullable)

UserPantrySignal (from past orders, simplified for MVP)
  user_id, sku_id, last_purchased_at
```

## 6. API Design (illustrative)

```
POST /videos/extract
  body: { video_url, user_id }
  returns: { job_id }

GET /videos/extract/{job_id}
  returns: { status: "processing"|"done"|"failed", cart_draft_id? }

GET /cart-drafts/{cart_draft_id}
  returns: {
    line_items: [
      { sku_id, name, quantity, unit, category, confidence, source }
    ],
    equipment_suggestions: [
      { name, reason: "recipe requires this", suppressed: bool }
    ],
    skipped_staples: [ "salt", "water" ]
  }

PATCH /cart-drafts/{cart_draft_id}/line-items/{line_item_id}
  body: { quantity? , remove?: true }

POST /cart-drafts/{cart_draft_id}/checkout
  returns: { blinkit_cart_id }
```

## 7. The Core AI Prompt (extraction + classification step)

This is the heart of the product — the single LLM call that turns transcript + frames into structured, correctly-classified data.

```
SYSTEM:
You are a cooking-video ingredient extractor for a grocery shopping assistant.
You will be given a video transcript (may be partial or auto-generated, expect
noise) and a set of sampled frame descriptions from a cooking video.

Your job: extract every food item AND every piece of cooking equipment
mentioned or clearly shown, then classify each one.

Classification rules:
- "consumable": an ingredient that gets used up and would need to be
  purchased for this recipe (e.g. chicken, onions, turmeric, paneer).
- "staple": a consumable so commonly already owned that it should NOT be
  auto-added to a cart (salt, water, cooking oil in small quantity, black
  pepper). Use judgment — a staple in one context (a pinch of salt) can be
  a real purchase in another (2kg of salt for pickling).
- "equipment": a reusable tool or appliance, not consumed (pressure cooker,
  mixer grinder, tawa, oven, air fryer). These should NEVER be silently
  added to a cart — only ever surfaced as an optional suggestion.

For each item return:
- name (normalized, singular, lowercase)
- category: consumable | staple | equipment
- estimated_quantity and unit if determinable from context (else null)
- confidence: 0-1, how sure you are this item is actually needed for
  this specific recipe (not just mentioned in passing)

Be conservative: if something is ambiguous (e.g. "cooker" without clarity
on whether it's a pressure cooker, rice cooker, or slow cooker), lower
confidence rather than guessing.

Return ONLY valid JSON, no prose, no markdown fences, in this shape:
{
  "items": [
    { "name": "...", "category": "...", "estimated_quantity": ..., "unit": "...", "confidence": ... }
  ]
}

USER:
Transcript:
"""
{transcript_text}
"""

Sampled frame descriptions (in order):
{frame_descriptions}
```

**Why this prompt is structured this way:**
- The consumable/staple/equipment split is spelled out with examples, because this is the exact judgment call that separates a good product from an annoying one (see the pressure-cooker discussion).
- Asking for `confidence` per item lets the app hide low-confidence guesses instead of cluttering the cart.
- Forcing pure JSON output means the backend can parse it directly with no regex cleanup.
- Explicit "be conservative" instruction reduces false positives on ambiguous equipment mentions — better to under-suggest than to add something wrong to a cart.

## 8. Iteration Plan

Each iteration is a self-contained milestone with a working demo at the end. Don't move to the next until the current one's acceptance criteria pass.

---

### Iteration 0 — Project Scaffolding
**Goal:** empty but running skeleton, no AI yet.
- Set up FastAPI backend with a health-check endpoint.
- Set up Postgres (Supabase) with the schema from Section 5.
- Set up a bare-bones iOS SwiftUI app with a text field for pasting a video URL (skip the real Share Extension for now — that's Iteration 6).
- Mock Blinkit catalog: seed ~50-100 grocery items with names, categories, pack sizes.

**Acceptance criteria:** paste a URL, hit "submit," get a hardcoded fake response back end-to-end.

---

### Iteration 1 — Text-Only Recipe → Cart (no video yet)
**Goal:** prove the extraction → classification → SKU-match pipeline works, using a plain-text recipe as input (skip video entirely).
- Build `/videos/extract` endpoint that accepts raw recipe text instead of a URL.
- Wire up the core AI prompt (Section 7) against that text.
- Build simple embedding-based SKU matching against the mock catalog.
- Return a cart draft JSON.

**Acceptance criteria:** paste a text recipe ("butter chicken: chicken, butter, cream, garam masala, tomatoes...") and get back a correctly classified, SKU-matched cart draft.

---

### Iteration 2 — Real Video Ingestion (captions path only)
**Goal:** handle actual video URLs where captions/transcripts are available (most YouTube cooking videos have these).
- Integrate `yt-dlp` to fetch video metadata + existing captions.
- Feed captions into the same pipeline from Iteration 1.
- Add async job handling (Celery/Redis) since fetching + processing takes a few seconds.

**Acceptance criteria:** share a real YouTube recipe video URL with captions, get a correct cart draft within ~10-15 seconds.

---

### Iteration 3 — Audio Fallback (no captions)
**Goal:** handle Instagram Reels / videos with no captions.
- Add audio extraction (`ffmpeg`) + Whisper transcription as a fallback when no captions exist.
- Handle short/silent videos gracefully (return partial results, flag low confidence).

**Acceptance criteria:** a captionless Instagram reel of someone cooking produces a reasonable cart draft (even if less complete than the captioned case).

---

### Iteration 4 — Visual Understanding (frame sampling)
**Goal:** catch ingredients/equipment that are *shown* but never *said* (very common in cooking videos — someone just holds up an onion without narrating).
- Add `ffmpeg` frame sampling (e.g. 1 frame every 5-8 seconds).
- Feed frame descriptions (via a vision-capable model call) alongside the transcript into the core extraction prompt.

**Acceptance criteria:** a video where an ingredient is shown but never mentioned out loud still gets picked up (test with a couple of real reels manually).

---

### Iteration 5 — Equipment Suppression Logic
**Goal:** implement the consumable/staple/equipment behavior properly (this is the differentiating feature from the concept discussion).
- Ensure equipment items are never auto-added to the cart — only surfaced as a dismissible suggestion.
- Wire up the `UserPantrySignal` table (mocked purchase history) and suppress equipment suggestions for items the user has ordered before.
- Ensure staples are shown as a "you probably already have these" list, not in the cart.

**Acceptance criteria:** a "pressure cooker" recipe does NOT add a pressure cooker to the cart; if the mock user has "purchased" one before, the suggestion doesn't even appear.

---

### Iteration 6 — SKU Matching Quality + Pack Sizes
**Goal:** move from naive matching to something that feels genuinely useful.
- Improve embedding-based matching with fallback to exact-name matching first.
- Add pack-size heuristics (e.g. default to smallest pack for a single recipe, scale up if quantity is large).
- Handle out-of-stock/substitution logic (basic version: suggest next-closest SKU).

**Acceptance criteria:** ingredient quantities map to sensible real-world pack sizes, not arbitrary defaults.

---

### Iteration 7 — iOS Share Extension (real UX)
**Goal:** replace the "paste a URL" placeholder with the real share-sheet flow.
- Build an actual iOS Share Extension that appears when sharing a YouTube/Instagram video.
- Show a loading state, then the editable cart draft screen.
- Allow removing/adjusting line items before "Add to Blinkit Cart."

**Acceptance criteria:** from the YouTube or Instagram app, tap Share → Blinkit, and land on an editable cart within ~15 seconds.

---

### Iteration 8 — Polish, Edge Cases, Demo Hardening
**Goal:** make the demo bulletproof.
- Handle failure states gracefully (video too long, no recipe content detected, network errors).
- Add a "confidence" UI indicator so users see which items the AI is less sure about.
- Pick and pre-test 2-3 known-good demo videos (one with captions, one without, one with a visible-but-unspoken equipment item) so the live demo is reliable.

**Acceptance criteria:** the three demo scenarios (captioned / captionless / equipment-suppression) all work reliably, repeatedly, live.

---

## 9. Suggested Order of Work (if time is short)

If you only have hackathon time for a subset: **Iterations 0 → 1 → 2 → 5 → 7** gets you a real end-to-end demo (text/caption-based extraction, correct equipment suppression, real share-sheet UX) even if you skip audio fallback (3) and visual frame sampling (4). Those two are the most impressive but also the most time-consuming — add them only if time remains.

## 10. Kickoff Prompt (paste this into Claude Code / your AI coding agent to start)

```
I'm building "AI Video Recipe Shopping" — a feature where a user shares a
cooking video URL (YouTube/Instagram) and the system extracts ingredients,
classifies them as consumable/staple/equipment, matches them to grocery
SKUs, and returns an editable cart draft.

Stack: FastAPI backend, Postgres (Supabase) with pgvector, Celery+Redis for
async jobs, yt-dlp for video metadata/captions, Whisper for audio fallback,
ffmpeg for frame sampling, Claude API for extraction/classification,
embeddings for SKU matching. iOS SwiftUI client with a Share Extension.

Let's build this iteratively. Start with Iteration 0 from the plan below:
set up the FastAPI skeleton with a health-check endpoint, the Postgres
schema (Video, ExtractedItem, SkuMatch, CartDraft, CartLineItem,
UserPantrySignal tables), and seed a mock grocery catalog of ~75 items
across produce, dairy, spices, and packaged goods. Don't build the AI
pipeline yet — just get the scaffolding running with a hardcoded fake
response so I can verify the plumbing end-to-end.

Once that's confirmed working, we'll move to Iteration 1: wiring up the
core extraction prompt against plain text recipes before touching real
video ingestion.

[Paste full iteration plan / architecture doc here for reference]
```

Use this same pattern for each subsequent iteration: paste the specific iteration's goal + acceptance criteria from Section 8, and let the agent implement just that slice before moving on. Keeping each request scoped to one iteration (rather than "build the whole thing") is what keeps the AI's output reviewable and correct.
