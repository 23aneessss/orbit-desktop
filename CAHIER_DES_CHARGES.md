# Cahier des Charges — Orbit (macOS / Swift)

> **Document de référence pour la recréation native d'Orbit sur macOS avec Swift / SwiftUI / SwiftData.**
> Version source : Orbit 1.0.0 (Next.js 16 + SQLite + Drizzle ORM).
> Destiné à un agent AI chargé de l'implémentation complète.

---




## Table des matières

1. [Vue d'ensemble du projet](#1-vue-densemble-du-projet)
2. [Identité et principes de conception](#2-identité-et-principes-de-conception)
3. [Stack technique cible (macOS / Swift)](#3-stack-technique-cible-macos--swift)
4. [Architecture applicative](#4-architecture-applicative)
5. [Modèle de données (schéma complet)](#5-modèle-de-données-schéma-complet)
6. [Identité visuelle et design system](#6-identité-visuelle-et-design-system)
7. [Interface — Structure des fenêtres / navigation](#7-interface--structure-des-fenêtres--navigation)
8. [Fonctionnalités détaillées](#8-fonctionnalités-détaillées)
9. [Algorithmes et logique métier clés](#9-algorithmes-et-logique-métier-clés)
10. [Command palette et raccourcis clavier](#10-command-palette-et-raccourcis-clavier)
11. [Paramètres et préférences](#11-paramètres-et-préférences)
12. [Export / Import de données](#12-export--import-de-données)
13. [Points critiques et pièges à éviter](#13-points-critiques-et-pièges-à-éviter)
14. [Roadmap](#14-roadmap)
15. [Annexe — Correspondances Web → macOS](#15-annexe--correspondances-web--macos)

---

## 1. Vue d'ensemble du projet

### 1.1 Nom

**Orbit**

### 1.2 Tagline

> Your personal universe — habits, ideas, tasks & people.

### 1.3 Sous-titre

> LOCAL-FIRST · KEYBOARD-FIRST · YOURS

### 1.4 Objectif

Orbit est un **système d'exploitation personnel local-first** qui unifie en une seule application calme et sobre quatre dimensions de la vie quotidienne :

- **Habitudes** — suivi par heatmap de contribution (style GitHub), streaks, objectifs hebdomadaires.
- **Idées** — éditeur sans distraction avec tags, épinglage, et un canvas spatial pour relier et fusionner les idées.
- **Tâches & Workflows** — tâches simples ou composites (sous-étapes arborescentes), vue liste + vue board (canvas), workflow editor node-based avec annotations manuscrites.
- **Contacts** — CRM léger : fiches personnes, timeline d'interactions, follow-ups.

### 1.5 Philosophie

| Principe | Description |
|---|---|
| **Local-first** | Toutes les données dans un seul fichier sur disque. Aucun compte, aucune synchronisation, aucun telemetry, aucune requête réseau. L'utilisateur possède ses données et peut exporter à tout moment. |
| **Keyboard-first** | `⌘K` atteint tout (navigation, actions, log d'habitudes). `⌘+Enter` pour soumettre. Le clavier est le moyen d'interaction principal. |
| **Une seule couleur d'accent** | Une couleur d'accent unique (choisie par l'utilisateur) imprègne toute l'interface : boutons, états actifs, focus rings, heatmaps, progress rings, liens, bords du canvas, logo. |
| **Sobre et neutre** | Polices système, pas de clutter, palette neutre chaude (crème / charbon avec sous-ton brun — pas de gris pur), bordures fines 1px, ombres légères, coins arrondis 10–14px. |

### 1.6 Utilisateur cible

Utilisateur unique (single-user). Aucune authentification, aucun système de comptes. La seule "identité" est le nom d'affichage (`settings.name`) utilisé dans le message d'accueil de la page d'accueil.

---

## 2. Identité et principes de conception

### 2.1 Logo / Mark

Un **orbit** : une tuile carrée arrondie (radius ~7.5px) avec un dégradé diagonal (`#5b82f5` → `#3d6df2`, ou dérivé de la couleur d'accent en live), contenant :

- Une **planète** blanche (cercle central ~3.4px de rayon).
- Un **anneau orbital** (rayon ~9.3px, trait blanc 1.8px à 92% d'opacité), incliné.
- Un **satellite** en haut à droite (position ~22.58, 9.42) qui crée un **gap propre** dans l'anneau via un halo de même couleur que la tuile + un petit cercle blanc (2.5px).

Le logo doit **suivre la couleur d'accent** en live (dégradé dérivé de `--accent`). Sur macOS, utiliser `LinearGradient` avec la couleur d'accent comme point de départ.

### 2.2 Wordmark

« Orbit » en police système, **semibold**, tracking serré. Accolé au logo dans la sidebar.

### 2.3 Couleurs — Base neutre chaude

La palette est volontairement **chaude** (sous-ton brun/beige), jamais gris pur.

#### Thème clair (`:root`)

| Token | Valeur | Usage |
|---|---|---|
| `--canvas` | `#f7f6f3` | Fond de l'app (crème chaud) |
| `--surface` | `#ffffff` | Cartes |
| `--sunken` | `#f2f0ec` | Insets, survols |
| `--line` | `#e9e7e1` | Bordures fines |
| `--line-strong` | `#d8d5ce` | Bordures accentuées |
| `--ink` | `#1c1a17` | Texte principal (noir chaud) |
| `--ink-2` | `#6f6b63` | Texte secondaire |
| `--ink-3` | `#a5a199` | Texte tertiaire / placeholder |
| `--heat-zero` | `#edeae3` | Cellule heatmap niveau 0 |
| `--danger` | `#dc2626` | Erreur / destructif |
| `--warn` | `#b45309` | Avertissement (follow-up due today) |
| `--ok` | `#047857` | Succès |
| `--tooltip-bg` | `#26231f` | Fond tooltip |
| `--tooltip-fg` | `#f7f6f3` | Texte tooltip |

#### Thème sombre (`[data-theme="dark"]`)

| Token | Valeur |
|---|---|
| `--canvas` | `#131211` |
| `--surface` | `#1c1a18` |
| `--sunken` | `#262421` |
| `--line` | `#2c2a26` |
| `--line-strong` | `#403d37` |
| `--ink` | `#f1efeb` |
| `--ink-2` | `#a19d94` |
| `--ink-3` | `#6d6961` |
| `--heat-zero` | `#262421` |
| `--danger` | `#f87171` |
| `--warn` | `#fbbf24` |
| `--ok` | `#34d399` |
| `--tooltip-bg` | `#f1efeb` |
| `--tooltip-fg` | `#26231f` |

### 2.4 Couleur d'accent

- **Valeur par défaut :** `#3d6df2` (Cobalt).
- **8 presets :** Cobalt `#3d6df2`, Indigo `#6366f1`, Violet `#8b5cf6`, Emerald `#10b981`, Teal `#0ea5a8`, Amber `#f59e0b`, Rose `#f43f5e`, Graphite `#52525b`.
- **Custom :** color picker natif (`ColorPicker` sur macOS / `NSColorWell`).
- **Shades dérivées** (via `color-mix(in oklab, ...)`) — sur macOS, calculer avec `Color.mix` ou des composantes :

| Shade | Formule | Usage |
|---|---|---|
| `accent-strong` | accent 84% + noir | Hover/pressé bouton primaire |
| `accent-soft` | accent 13% + surface | Fond léger (badges, empty states) |
| `accent-softer` | accent 7% + surface | Fond encore plus léger |
| `accent-border` | accent 34% + line | Bordure accent douce |
| `accent-ink` | accent 72% + ink | Texte sur fond accent-soft |

### 2.5 Échelle de heatmap

5 niveaux (`--heat-0` à `--heat-4`) :

| Niveau | Formule |
|---|---|
| `heat-0` | `var(--heat-zero)` (cellule vide) |
| `heat-1` | accent 22% + surface |
| `heat-2` | accent 46% + surface |
| `heat-3` | accent 70% + surface |
| `heat-4` | `var(--accent)` (plein) |

**Thresholds :**
- Heatmap d'activité globale (home) : `[1, 2, 4, 6]` → niveaux 1–4 (basé sur le compte d'activités du jour).
- Heatmap par habitude : `[1, 1, 1, 1]` → binaire (n'importe quel check-in = niveau max).

### 2.6 Couleurs des annotations (board)

6 couleurs pour sticky-notes et traits manuscrits :

| Slug | Couleur | Usage |
|---|---|---|
| `amber` | `#e0a400` | Défaut sticky-note |
| `blue` | `var(--accent)` | Bleu = accent |
| `green` | `#12a150` | Vert |
| `pink` | `#e0568b` | Rose |
| `violet` | `#8b5cf6` | Violet |
| `slate` | `#64748b` | Défaut crayon |

### 2.7 Couleurs d'habitudes

7 swatches pour la coloration par habitude :

| Nom | Valeur |
|---|---|
| Accent | `var(--accent)` (suit l'accent global) |
| Cobalt | `#3d6df2` |
| Emerald | `#10b981` |
| Violet | `#8b5cf6` |
| Amber | `#f59e0b` |
| Rose | `#f43f5e` |
| Teal | `#0ea5a8` |

### 2.8 Typographie

- **Police :** police système uniquement. Sur macOS → `SF Pro Text` / `SF Pro Display` (via `.system` / `.font(.system(...))`). Aucune police web personnalisée.
- **Tailles :**
  - Titres de page : 22–26px, semibold, tracking serré.
  - Titres de section : 15px, semibold.
  - Corps : 13–14px, regular.
  - Méta / labels : 11–12.5px.
  - Labels majuscules : 11px, tracking-wider, uppercase.
  - Comptes : `tabular-nums` (`.monospacedDigit()` sur macOS).
- **Line-height :** 1.75 dans l'éditeur d'idées (confort de lecture), ~1.5 ailleurs.

### 2.9 Iconographie

- **Source web :** lucide-react (Flame, Lightbulb, Waypoints, ListChecks, Users, Home, Settings, Search, Plus, Check, Pin, Trash2, Pencil, Star, ArrowRight, etc.). Stroke width ~1.9 (2.2 pour l'état actif).
- **Équivalent macOS :** `SF Symbols` — mapper chaque icône lucide vers son équivalent SF Symbol. Liste de mapping fournie en annexe §15.
- **16 icônes d'habitudes** (slugs → symboles) : target, code, dumbbell, book-open, pen-line, brain, droplets, moon, leaf, guitar, camera, bike, heart, coffee, languages, briefcase.

### 2.10 Patterns UI

| Pattern | Description |
|---|---|
| **Cartes** | Surface blanche, bordure 1px, radius 14px, ombre subtile `0 1px 2px rgb(32 28 20 / 0.03)`. |
| **Sidebar** | 256px étendue / 64px repliée. Persiste l'état dans UserDefaults (`orbit:sidebar-collapsed`). |
| **Topbar** | 56px de haut. Breadcrumbs ("Orbit › Section › Détail"). Date du jour à droite, bouton thème, avatar. |
| **Segmented controls** | Bascules de vue (List/Board, Steps/Workflow, Last 12 months / This year / Last year). → `Picker(.segmented)` sur macOS. |
| **Dropdown menus** | Actions par ligne (edit/delete/pin). → `Menu` sur macOS. |
| **Dialogs modaux** | Centrés, 400–560px, animation pop-in. → `Sheet` ou `.alert` / fenêtre séparée. |
| **Confirm dialogs** | Pour actions destructives (delete, wipe). |
| **Toasts** | Bottom-right, thémés. → `NSAlert` ou système de toast custom. |
| **Empty states** | Icône dans tuile accent-soft + titre + description + CTA. |
| **Avatars** | Initiales, hue déterministe depuis hash du nom (`hueFromString` : hash ×31 mod 360), couleurs oklch. |
| **Progress rings** | Anneau circulaire SVG (web) → cercle `Path` + `trim` sur macOS. |
| **Heatmaps** | Grille GitHub-style, Monday-first, tooltips au survol, click pour toggler. |
| **Sticky-notes** | Coins carrés, coin inférieur droit "pelé" (clip-path `::after`), ombres layer, 6 teintes. |
| **Canvas** | Grille de points en fond, zoom/pan, bords bezier flottants, zoom 0.2–1.75. |
| **Toolbar annotations** | Hand / Pencil / StickyNote + 6 swatches + Undo. |
| **Command palette** | `⌘K`, top-center, 560px, groupes avec en-têtes majuscules. |

### 2.11 Densité

Calme et spacieuse : contenu max-w ~1152px (max-w-6xl), padding 32px, gap 16–20px entre cartes, whitespace généreux, aucun bruit visuel.

---

## 3. Stack technique cible (macOS / Swift)

| Couche | Original (Web) | Cible (macOS) |
|---|---|---|
| Framework UI | Next.js 16 (React 19, App Router) | **SwiftUI** (macOS 14+ / Sonoma minimum) |
| Langage | TypeScript | **Swift 5.9+** |
| Persistence | SQLite via `@libsql/client` + Drizzle ORM | **SwiftData** (ou Core Data / SQLite direct via `SQLite.swift`) |
| Base de données | Fichier `data/orbit.db` | Fichier dans `Application Support/Orbit/orbit.db` ou container SwiftData |
| Canvas (React Flow) | `@xyflow/react` v12 | **Canvas custom SwiftUI** (zoom/pan gesture + `ZStack` de nodes) ou `SceneKit` / `PDFView` |
| Styling | Tailwind CSS v4 | **SwiftUI modifiers** + design tokens en `Color` extensions |
| Iconographie | lucide-react | **SF Symbols** |
| Command palette | cmdk (Radix) | **Command palette custom** (`SearchField` + liste filtrée) ou `.searchable()` |
| Toasts | sonner | **Toast custom** (overlay `ZStack`) ou `NSAlert` |
| Dates | date-fns v4 | **Foundation** (`Date`, `Calendar`, `DateFormatter`, `RelativeDateTimeFormatter`) |
| Menus / Dialogs | Radix UI | **SwiftUI natif** (`Menu`, `Sheet`, `Alert`, `ConfirmationDialog`) |
| State | Server components + `useState` | **@Observable** (Observation framework) + `@Query` (SwiftData) |
| Animations | CSS transitions/keyframes | **SwiftUI animations** (`.animation`, `withAnimation`, `.transition`) |
| IDs | `crypto.randomUUID()` | `UUID()` |
| JSON tags | `JSON.stringify` / parse | `JSONEncoder` / `JSONDecoder` |

### 3.1 Architecture recommandée (macOS)

```
Orbit/
├── App/
│   └── OrbitApp.swift              // @main, WindowGroup, injection du model container
├── Models/                         // SwiftData @Model classes (→ §5)
│   ├── Habit.swift
│   ├── HabitLog.swift
│   ├── Idea.swift
│   ├── IdeaLink.swift
│   ├── Contact.swift
│   ├── Interaction.swift
│   ├── Task.swift
│   ├── TaskStep.swift
│   ├── StepLink.swift
│   ├── BoardNote.swift
│   ├── BoardStroke.swift
│   └── AppSettings.swift           // singleton ou KV store
├── ViewModels/                     // @Observable controllers
│   ├── HabitsViewModel.swift
│   ├── IdeasViewModel.swift
│   ├── CanvasViewModel.swift
│   ├── TasksViewModel.swift
│   ├── PeopleViewModel.swift
│   ├── SettingsViewModel.swift
│   └── CommandPaletteViewModel.swift
├── Views/
│   ├── Layout/
│   │   ├── SidebarView.swift
│   │   ├── TopbarView.swift
│   │   └── ContentView.swift       // NavigationSplitView
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── TodayChecklistView.swift
│   │   ├── FollowUpsCardView.swift
│   │   └── RecentIdeasView.swift
│   ├── Habits/
│   │   ├── HabitsBoardView.swift
│   │   ├── HabitCardView.swift
│   │   ├── HabitDialogView.swift
│   │   └── HeatmapView.swift
│   ├── Ideas/
│   │   ├── IdeasBrowserView.swift
│   │   ├── IdeaCardView.swift
│   │   └── IdeaEditorView.swift
│   ├── Canvas/
│   │   ├── IdeaCanvasView.swift
│   │   ├── IdeaNodeView.swift
│   │   ├── FloatingEdgeView.swift
│   │   └── MergeDialogView.swift
│   ├── Tasks/
│   │   ├── TasksView.swift
│   │   ├── TaskBoardView.swift
│   │   ├── TaskDetailView.swift
│   │   ├── TaskDialogView.swift
│   │   ├── WorkflowCanvasView.swift
│   │   ├── TaskNodesView.swift
│   │   └── Annotations/
│   │       ├── BoardAnnotationsView.swift
│   │       └── NoteNodeView.swift
│   ├── People/
│   │   ├── PeopleBrowserView.swift
│   │   ├── PersonDetailView.swift
│   │   └── ContactDialogView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── ProfileFormView.swift
│   │   ├── AppearanceFormView.swift
│   │   └── DataSectionView.swift
│   ├── CommandPalette/
│   │   └── CommandPaletteView.swift
│   └── Components/                 // UI primitives réutilisables
│       ├── Button.swift
│       ├── Badge.swift
│       ├── Avatar.swift
│       ├── ProgressRing.swift
│       ├── SegmentedControl.swift
│       ├── EmptyStateView.swift
│       ├── ConfirmDialogView.swift
│       ├── KbdView.swift
│       └── LogoView.swift
├── Utils/
│   ├── DateUtils.swift             // buildWeeks, calcStreaks, ranges, formatting
│   ├── ColorUtils.swift            // color-mix, hueFromString, oklch, accent shades
│   ├── StringUtils.swift           // excerpt, initials, wordCount, readTime
│   ├── TagUtils.swift              // parseTags
│   └── BoardColors.swift           // palette annotations
└── Services/
    ├── ExportService.swift         // JSON export
    ├── SeedService.swift           // seed initial data
    └── RecomputeService.swift      // task completion roll-up
```

### 3.2 Navigation

Utiliser `NavigationSplitView` (three-column sur macOS) :

- **Sidebar** : navigation principale (Home, Habits, Ideas, Canvas, Tasks, People, Settings) + carte "Today" avec ProgressRing.
- **Content** : la vue principale de chaque section.
- **Detail** : pour les vues de détail (idea editor, person profile, task detail) — peut être un `NavigationLink` dans le content ou une colonne dédiée.

Le collapsed state de la sidebar se persiste dans `UserDefaults` (clé `orbit:sidebar-collapsed`).

---

## 4. Architecture applicative

### 4.1 Flux de données (original → cible)

**Original (Next.js) :**
- Pages = async server components → query Drizzle → pass props aux client components.
- Mutations = server actions → `revalidatePath("/", "layout")` → re-render complet depuis la DB.

**Cible (SwiftUI) :**
- Views observent des `@Observable` ViewModels qui wrappent `@Query` SwiftData ou `ModelContext`.
- Mutations = appels directs sur `ModelContext` + `try modelContext.save()`.
- L'UI se met à jour automatiquement via `@Query` / `@Observable` (pas de revalidation manuelle).
- **Pas de réseau, pas de server actions** — tout est local, synchrone, dans le même processus.

### 4.2 State management

- **Pas de store global type Redux/Zustand.** Chaque ViewModel est `@Observable` et scoped à sa section.
- **Prefs UI persistées dans UserDefaults :**
  - `orbit:sidebar-collapsed` (`"1"` / `"0"`)
  - `orbit:tasks-mode` (`"list"` / `"board"`)
  - `orbit:task-detail-mode` (`"steps"` / `"workflow"`)
- **Settings app (nom, accent, thème)** : stockés dans SwiftData (table `AppSettings` / KV store) — pas dans UserDefaults car ils font partie des données exportables.

### 4.3 Optimistic UI

Pattern : modifier l'état local immédiatement, appeler la mutation, rollback en cas d'erreur + toast. Sur macOS avec SwiftData, les mutations sont synchromes et fiables (pas de réseau), donc l'optimistic UI est moins critique — mais le pattern reste utile pour les opérations de canvas (drag, strokes) où l'on veut une réponse immédiate avant le save.

### 4.4 Thème (light / dark / system)

- Trois modes : Light, Dark, System.
- Sur macOS : `.preferredColorScheme(nil)` pour system, `.preferredColorScheme(.light)` / `.dark`.
- Le thème se persiste dans SwiftData (table settings).
- L'accent color s'applique via une `@Observable` `ThemeManager` qui expose `Color accent` — toutes les vues lisent cette couleur.

### 4.5 Accent scoping

Une habitude peut avoir sa propre couleur d'accent (`habit.color`). Quand on affiche sa carte/heatmap, l'accent local override l'accent global. Sur macOS : passer la couleur en paramètre aux sous-vues (heatmap, badges, progress ring) plutôt que via une variable globale.

---

## 5. Modèle de données (schéma complet)

> **Note :** Tous les IDs sont `UUID`. Toutes les dates de création sont `Date` (auto à l'insertion). Les dates métier (habit log date, interaction date, follow-up) sont stockées en `String` format `YYYY-MM-DD` pour permettre un tri calendaire simple — sur macOS, on peut utiliser `Date` avec `Calendar.startOfDay` pour la normalisation, mais le format string simplifie les comparaisons de jours.

### 5.1 `habits`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | `UUID()` | |
| `name` | String | — | notNull |
| `icon` | String | `"target"` | slug parmi 16 icônes (voir §2.9) |
| `color` | String | `"accent"` | slug : accent / cobalt / emerald / violet / amber / rose / teal |
| `targetPerWeek` | Int | `7` | clampé 1–7 |
| `createdAt` | Date | `now` | |

### 5.2 `habit_logs`

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `habitId` | UUID (FK → habits, cascade delete) | |
| `date` | String (`YYYY-MM-DD`) | |

**Contrainte :** Unique sur `(habitId, date)` — une seule entrée par jour par habitude. Toggler = insérer ou supprimer la ligne.

### 5.3 `ideas`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | | |
| `title` | String | `""` | |
| `content` | String | `""` | |
| `tags` | `[String]` (JSON) | `[]` | encoder en JSON dans SwiftData si pas de support natif d'arrays |
| `pinned` | Bool | `false` | |
| `createdAt` | Date | `now` | |
| `updatedAt` | Date | `now` | mis à jour à chaque save |
| `canvasX` | Double? | `nil` | nil = non placé sur le canvas |
| `canvasY` | Double? | `nil` | |

### 5.4 `idea_links`

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `ideaAId` | UUID (FK → ideas, cascade) | toujours le plus petit UUID (normalisation) |
| `ideaBId` | UUID (FK → ideas, cascade) | toujours le plus grand UUID |

**Contrainte :** Unique sur `(ideaAId, ideaBId)`. Paire stockée normalisée (A < B par comparaison d'UUID) pour dédupliquer quelle que soit la direction du drag. Liens **non orientés**.

### 5.5 `contacts`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | | |
| `name` | String | — | notNull |
| `email` | String? | `nil` | |
| `phone` | String? | `nil` | |
| `company` | String? | `nil` | |
| `role` | String? | `nil` | |
| `tags` | `[String]` (JSON) | `[]` | |
| `favorite` | Bool | `false` | |
| `lastContactedAt` | String? (`YYYY-MM-DD`) | `nil` | mis à jour quand une interaction plus récente est ajoutée |
| `nextFollowUp` | String? (`YYYY-MM-DD`) | `nil` | date du prochain follow-up |
| `createdAt` | Date | `now` | |

### 5.6 `interactions`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | | |
| `contactId` | UUID (FK → contacts, cascade) | | |
| `kind` | String | `"note"` | valeurs : `note` / `call` / `meeting` / `message` / `email` |
| `note` | String | — | notNull |
| `date` | String (`YYYY-MM-DD`) | | date de l'interaction (max = aujourd'hui) |
| `createdAt` | Date | `now` | |

### 5.7 `tasks`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | | |
| `title` | String | — | notNull |
| `note` | String | `""` | |
| `done` | Bool | `false` | simple : toggled directement ; complexe : dérivé via `recomputeTask` |
| `canvasX` | Double? | `nil` | position sur le board |
| `canvasY` | Double? | `nil` | |
| `createdAt` | Date | `now` | |
| `completedAt` | Date? | `nil` | set quand `done` passe à true |

### 5.8 `task_steps`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | | |
| `taskId` | UUID (FK → tasks, cascade) | | |
| `parentId` | UUID? (FK → task_steps, cascade) | `nil` | nil = top-level |
| `title` | String | — | notNull |
| `done` | Bool | `false` | leaf : toggled ; composite : dérivé |
| `orderIdx` | Int | `0` | ordre dans la liste (steps mode) |
| `canvasX` | Double? | `nil` | position sur le workflow canvas |
| `canvasY` | Double? | `nil` | |
| `createdAt` | Date | `now` | |

**Index :** sur `parentId`. Une step avec des enfants est "composite" — son `done` est **dérivé** (complete uniquement si tous ses descendants leaf sont complete).

### 5.9 `step_links`

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `taskId` | UUID (FK → tasks, cascade) | |
| `sourceId` | UUID (FK → task_steps, cascade) | |
| `targetId` | UUID (FK → task_steps, cascade) | |

**Contrainte :** Unique sur `(sourceId, targetId)`. Liens **orientés** (visualisation). La complétion ne se propage **pas** via les liens — uniquement via la hiérarchie `parentId`.

### 5.10 `board_notes`

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `id` | UUID (PK) | | |
| `board` | String | | `"tasks"` pour le board global, `"task:<taskId>"` pour le workflow d'une tâche |
| `text` | String | `""` | |
| `color` | String | `"amber"` | slug parmi les 6 couleurs d'annotation |
| `x` | Double | | position canvas |
| `y` | Double | | |
| `createdAt` | Date | `now` | |
| `updatedAt` | Date | `now` | |

### 5.11 `board_strokes`

| Champ | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | |
| `board` | String | même convention que `board_notes` |
| `color` | String (`"slate"` par défaut) | |
| `points` | `[{x: Double, y: Double}]` (JSON) | coordonnées en espace canvas (flow coords), pas en espace écran |
| `createdAt` | Date | `now` |

### 5.12 `settings` (KV store)

| Champ | Type | Notes |
|---|---|---|
| `key` | String (PK) | |
| `value` | String | |

**Clés utilisées :**
- `name` (String, défaut `""`) — nom d'affichage pour le greeting.
- `accent` (String hex, défaut `#3d6df2`).
- `theme` (String : `"light"` / `"dark"` / `"system"`, défaut `"light"`).

### 5.13 Relations et cascades

```
habits ──< habit_logs (cascade delete)
ideas ──< idea_links (cascade, des deux côtés)
contacts ──< interactions (cascade)
tasks ──< task_steps (cascade)
task_steps ──< task_steps (self-ref, cascade — parent → enfants)
tasks ──< step_links (cascade)
task_steps ──< step_links (cascade, source + target)
```

`wipeAllData` supprime : habit_logs, habits, ideas, interactions, contacts. **Conserve** les settings (nom, accent, thème). Les tasks/steps/notes/strokes ne sont pas explicitement listés dans le wipe original — sur macOS, inclure TOUT sauf settings pour un wipe complet.

---

## 6. Identité visuelle et design system

*(Voir §2 pour les détails complets des couleurs, typographie, iconographie, patterns UI.)*

### 6.1 Design tokens (à implémenter comme extensions `Color`)

```swift
// Exemple de structure — à adapter
extension Color {
    // Thème courant (light ou dark) — déterminé par le ThemeManager
    static var canvas: Color { ... }
    static var surface: Color { ... }
    static var sunken: Color { ... }
    static var line: Color { ... }
    static var lineStrong: Color { ... }
    static var ink: Color { ... }
    static var ink2: Color { ... }
    static var ink3: Color { ... }
    static var danger: Color { ... }
    static var warn: Color { ... }
    static var ok: Color { ... }
    
    // Accent (dynamique, lu depuis ThemeManager)
    static var accent: Color { ... }
    static var accentStrong: Color { ... }  // accent + 16% black
    static var accentSoft: Color { ... }    // accent + 87% surface
    static var accentSofter: Color { ... }  // accent + 93% surface
    static var accentBorder: Color { ... }  // accent + 66% line
    static var accentInk: Color { ... }     // accent + 28% ink
    
    // Heat scale
    static var heatZero: Color { ... }
    static func heat(level: Int, accent: Color, surface: Color) -> Color { ... }
}
```

### 6.2 Card style

```swift
// Équivalent SwiftUI de .card
RoundedRectangle(cornerRadius: 14)
    .fill(Color.surface)
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line, lineWidth: 1))
    .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
```

### 6.3 Sticky note style

Coin pelé en bas à droite : utiliser un `Path` avec un clip-path qui coupe le coin, + une ombre layer, + un triangle diagonal en `::after` (sur macOS : un `Path` en overlay).

### 6.4 Animations

| Animation | Durée | Courbe |
|---|---|---|
| `fade-in` | 150ms | ease-out |
| `pop-in` (dialogs) | 200ms | opacity + scale 0.97 → 1.0 |
| `pop-in-sm` (menus) | 150ms | opacity + translateY -3px → 0 |
| Toggle heatmap | instant (optimistic) | — |
| Drag canvas | suit le geste | — |
| Progress ring | animated dashoffset | easeInOut |

---

## 7. Interface — Structure des fenêtres / navigation

### 7.1 Shell principal

```
┌─────────────────────────────────────────────────┐
│  [Sidebar]  │  Topbar (56px)                     │
│  (256/64px) │  Orbit › Section › Detail          │
│             │                    [date] [☀/🌙] [AV]│
│  ◉ Orbit    ├─────────────────────────────────────┤
│  🔍 Search   │                                     │
│             │                                     │
│  ⌂ Home      │     Content (scrollable)            │
│  🔥 Habits   │                                     │
│  💡 Ideas    │                                     │
│  ⊕ Canvas    │                                     │
│  ☑ Tasks     │                                     │
│  👥 People    │                                     │
│             │                                     │
│  ⚙ Settings  │                                     │
│  ─────────   │                                     │
│  ◐ Today     │                                     │
│  3/5         │                                     │
└─────────────────────────────────────────────────┘
```

- `NavigationSplitView` avec sidebar + detail.
- Hauteur full window (`h-dvh` → `.frame(maxHeight: .infinity)`).
- Overflow hidden sur le shell, scroll uniquement dans le content.

### 7.2 Sidebar

- **Largeur :** 256px étendue, 64px repliée.
- **Bouton collapse :** persiste dans UserDefaults (`orbit:sidebar-collapsed`).
- **Contenu :**
  - Logo + wordmark "Orbit" + bouton collapse.
  - Bouton Search (dispatch event → ouvre command palette, affiche `⌘K`).
  - Items de navigation : Home, Habits, Ideas, Canvas, Tasks, People (icône + label).
  - Footer : Settings (item de nav) + carte "Today" avec `ProgressRing` (habitsDone/habitsTotal) + label "N/M".
- **État replié :** icônes uniquement, tooltips au survol.

### 7.3 Topbar

- **Hauteur :** 56px.
- **Gauche :** Breadcrumbs ("Orbit › Section › Détail") dérivés du chemin courant.
  - `SECTIONS` : habits, ideas, canvas, tasks, people, settings.
  - `DETAIL` : label spécifique quand on est sur une page de détail (idea title, person name, task title).
- **Droite :** Date du jour (format `EEE, MMM d`), bouton thème (Sun/Moon, toggle light↔dark), Avatar (initiales, lien vers /settings).

### 7.4 Pages / routes

| Route | Vue | Description |
|---|---|---|
| `/` | HomeView | Dashboard d'accueil |
| `/habits` | HabitsBoardView | Board des habitudes |
| `/ideas` | IdeasBrowserView | Navigateur d'idées |
| `/ideas/:id` | IdeaEditorView | Éditeur d'une idée |
| `/canvas` | IdeaCanvasView | Canvas spatial d'idées |
| `/tasks` | TasksView | Liste + board des tâches |
| `/tasks/:id` | TaskDetailView | Détail d'une tâche (steps / workflow) |
| `/people` | PeopleBrowserView | Table des contacts |
| `/people/:id` | PersonDetailView | Profil d'une personne |
| `/settings` | SettingsView | Profil, apparence, données, about |

Sur macOS : utiliser `NavigationLink` dans la sidebar pour la navigation principale, et `NavigationLink` dans les listes pour les détails. Pas de URL routing explicite nécessaire (sauf si on veut deep-linking).

---

## 8. Fonctionnalités détaillées

### 8.1 Home Dashboard

**Layout :**
1. **Greeting** : selon l'heure — "Up late" (avant 5h) / "Good morning" (5h–12h) / "Good afternoon" (12h–18h) / "Good evening" (après 18h) + `settings.name` + date du jour.
2. **4 stat cards** (cliquables → navigation) :
   - **Current streak** : meilleur streak actuel parmi toutes les habitudes (`calcStreaks`).
   - **Today N/M** : habitudes faites aujourd'hui / total.
   - **Ideas** : nombre total d'idées + nombre éditées cette semaine.
   - **People** : nombre total de contacts + follow-ups due.
3. **Activity heatmap card** : heatmap unifiée 365 jours (habit logs + idea edits + interactions agrégés par jour), thresholds `[1,2,4,6]`, avec légende "Less □□□□□ More".
4. **Grille 2/3 + 1/3** :
   - Gauche : `TodayChecklist` (habitudes du jour avec toggle inline + barre de progression hebdomadaire).
   - Droite : `FollowUpsCard` (top 5 follow-ups, badges overdue/due/relative, "Mark done" au survol) + `RecentIdeas` (top 4 idées récentes, bouton "+" pour créer).

**Logique d'agrégation de l'heatmap :**
- Construire un `Map<dateISO, count>` en fusionnant : chaque habit log +1, chaque idea edit (updatedAt) +1, chaque interaction +1.
- Range : 365 derniers jours (du jour même jusqu'à 365 jours en arrière).

### 8.2 Habits

#### Habits Board (`/habits`)

- **Range toggle** (Segmented) : Last 12 months / This year / Last year.
- **Bouton "New habit"** → `HabitDialog`.
- **Empty state** si aucune habitude.
- **Liste de `HabitCard`** (une par habitude).

#### HabitCard

- **Accent scoping** : si `habit.color != "accent"`, wrapper dans un conteneur qui override l'accent local pour cette carte (heatmap + badges suivent la couleur de l'habitude).
- **Header** : icône (tuile arrondie accent-soft), nom, compte de check-ins, meilleur streak (Flame icon), badge streak actuel.
- **Bouton "Mark today" / "Done today"** : toggle optimiste du log d'aujourd'hui.
- **Dropdown** (⋮) : Edit (ouvre `HabitDialog` pré-rempli) / Delete (avec `ConfirmDialog`).
- **Heatmap** : 365 jours (ou selon range), binary thresholds `[1,1,1,1]`, click sur un jour pour toggler (dates futures désactivées).
- **Footer** : barre de progression hebdomadaire (check-ins cette semaine / targetPerWeek) + `HeatLegend`.

#### HabitDialog (create / edit)

- **Name** : text field.
- **Icon** : grille 8 colonnes de 16 icônes (cliquables, sélection mise en avant).
- **Color** : 7 swatches (Accent, Cobalt, Emerald, Violet, Amber, Rose, Teal).
- **Weekly target** : stepper −/+ clampé 1–7.

#### Logique de streak (`calcStreaks`)

```
best = longueur de la plus longue série de jours consécutifs dans l'ensemble des dates
current = à partir d'aujourd'hui (ou hier si aujourd'hui manquant), remonter tant que le jour existe dans l'ensemble
```

#### Logique de heatmap (`buildWeeks`)

- Monday-first : aligner le premier jour sur le lundi de sa semaine.
- 7 slots par semaine, `null` pour les jours hors range.
- Month labels espacés d'au moins 3 semaines pour éviter la surcharge.

### 8.3 Ideas

#### Ideas Browser (`/ideas`)

- **Search** : filtre sur title + content + tags.
- **Tag chips** : top 10 tags par fréquence, toggle de filtre.
- **Section Pinned** : idées épinglées en premier.
- **Section "Everything else"** : grille responsive (1/2/3 colonnes selon la largeur).
- **IdeaCard** : lien (navigation vers éditeur), indicateur pin, dropdown (Pin/Unpin, Delete avec confirm), excerpt 3 lignes, tags (2 premiers + "+N"), temps relatif.

#### Idea Editor (`/ideas/:id`)

- **Éditeur sans distraction** : textareas auto-resize (title + content).
- **Tags** : ajouter via Enter ou virgule, retirer via × ou Backspace sur input vide.
- **Autosave** : debounce 700ms → `updateIdea`. Indicateur de statut : "Saving…" / "Saved".
- **Pin button** : épingle l'idée.
- **Delete** : confirm → navigation back.
- **Sidebar (large screens)** : Stats card (word count, character count, read time MM:SS @ 200 wpm, created, edited).
- **Footer** : words · read time · last edited.

#### Canvas (`/canvas`)

- **Canvas infini** avec fond grille de points, zoom/pan, zoom 0.2–1.75.
- **Nodes** : chaque idée = une carte (224px de large, title + excerpt 3 lignes + tags + pin indicator). 4 handles (top/right/bottom/left) cachés jusqu'au survol/sélection.
- **Drag** : repositionner un node, save on drag stop.
- **Auto-tiling** : les idées non placées (canvasX/Y nil) sont disposées en grille 3 colonnes sous les nodes placés (280×170). Le tiling est persisté une fois (guard `tiledPersisted`).
- **Connect** : drag d'un handle vers un autre → crée un lien non orienté (normalisé A < B).
- **Edges** : bezier flottants, border-to-border (calcul d'intersection du ligne centre-à-centre avec le rectangle du node).
- **Double-click empty** : crée une idée à la position.
- **Double-click node** : ouvre l'éditeur.
- **Merge** : drag un node avec >50% de recouvrement sur un autre → ouvre `MergeDialog` :
  - Prévisualisation des deux côtés.
  - Title par défaut = titre du survivant (ou du merge si vide).
  - Content = contenu du survivant + `\n\n---\n\n` + contenu du merge.
  - Tags = union des deux.
  - `mergeIdeas(keepId, mergeId, merged)` : update le survivant, re-pointe tous les liens du merge vers le survivant (dédupe, drop le lien direct keep↔merge), delete le merge (cascade nettoie les anciens liens).

### 8.4 Tasks & Workflows

#### Tasks View (`/tasks`)

- **Mode toggle** (Segmented) : List / Board (persisté dans UserDefaults `orbit:tasks-mode`).
- **Bouton "New task"** → `TaskDialog`.
- **Ouverture auto** du dialog si `?new=1` (sur macOS : via un bouton ou un state flag).

#### List mode

- **Section "Open"** : tâches non complétées.
  - `TaskRow` : simple → checkbox toggle ; complexe → pill `stepsDone/stepsTotal` + badge "workflow" + dropdown delete.
- **Section "Completed"** : tâches complétées.

#### Board mode

- **Canvas React Flow** (équivalent macOS : canvas custom) sans edges.
- **Node types :**
  - `sticky` : tâche simple = sticky-note avec done toggle + note.
  - `progress` : tâche complexe = carte avec title, flèche "open workflow", progress bar + `stepsDone/stepsTotal`.
- **Auto-tiling** : unplaced tasks en grille 4 colonnes (260×150).
- **Drag** : save positions.
- **Double-click empty** : ouvre `TaskDialog` avec position.
- **Double-click node** : ouvre `/tasks/:id?view=workflow`.
- **BoardAnnotations** : couche d'annotations (pen + sticky notes) partagée avec le workflow canvas.

#### Task Detail (`/tasks/:id`)

- **Title éditable** : autosave debounce 600ms.
- **Mode toggle** (Segmented) : Steps / Workflow (persisté dans UserDefaults `orbit:task-detail-mode`, override par `?view=`).
- **Steps mode** :
  - Liste ordonnée des steps top-level.
  - `StepBlock` pour chaque step :
    - **Simple** : checkbox + title.
    - **Composite** : pill `doneKids/total` + bouton "Add sub-step" (input inline) + move up/down + delete.
    - Composite est complete **uniquement si tous ses descendants sont complete**.
- **Workflow mode** :
  - Canvas node-based editor.
  - Affiche les steps d'un niveau (parentId === current).
  - **Breadcrumb** : "Workflow › step › sub-step…" pour drill into composite steps.
  - `WorkflowStepNode` : title éditable (debounce 500ms), done toggle (simple) ou pill (composite), flèche open-sub-steps.
  - Connect steps → `createStepLink` (orienté, dédupe).
  - Double-click empty → `createStepAt` (avec position, title vide).
  - Delete via keyboard (Delete/Backspace, gardé contre la saisie de texte).
  - `BoardAnnotations` uniquement au root level.

#### Task Dialog (create)

- **Title** : text field.
- **Note** : textarea.
- **Steps** : textarea, une ligne = une step (chaque ligne → `addStep`).
- **Position optionnelle** (quand créé depuis le board).

#### Algorithme de complétion roll-up (`recomputeTask`)

```
1. Construire une map parent → enfants pour toutes les steps de la tâche.
2. Récursivement, isComplete(step) :
   - Si leaf (pas d'enfants) → return step.done
   - Si composite → return true si tous les enfants sont isComplete
   - Memoization via cache pour éviter les recalculs.
3. Persister les états `done` dérivés des composites qui ont dérivé.
4. task.done = true si toutes les steps top-level sont isComplete.
5. task.completedAt = now si newly done, nil si newly undone.
```

**Déclenché après** : addStep, toggleStep, deleteStep, moveStep, addSubStep.

**Protection** : `toggleStep` ignore les toggles directs sur les steps composites (seules les leaves sont toggglables).

### 8.5 Board Annotations (partagé Tasks board + Task workflow)

#### Toolbar (top-left du canvas)

- **Hand** : mode déplacement.
- **Pencil** : mode dessin.
- **StickyNote** : ajouter un commentaire.
- **6 color swatches** : amber / blue / green / pink / violet / slate.
- **Undo** (en mode pencil) : annule le dernier trait.

#### Pen (freehand)

- Pointer-capture (sur macOS : `DragGesture` sur une overlay fullscreen).
- Enregistre les points avec une distance minimale au carré de 4 (filtre les points redondants).
- Crée le stroke via `createStroke` (optimistic avec temp UUID, réconcilié avec l'ID réel).
- Dessine les strokes en SVG paths (sur macOS : `Path` dans l'espace canvas, pan/zoom avec le canvas).
- Stroke sélectionnable (ligne transparente large pour le hit-test).
- Delete / Backspace supprime le stroke sélectionné (garde contre la saisie de texte dans les inputs).

#### Sticky notes

- Esthétique papier réaliste : coin pelé en bas à droite (`::after` clip-path → `Path` overlay sur macOS).
- 6 couleurs (swatches qui apparaissent quand sélectionné).
- Bouton delete.
- Textarea autosave (debounce 500ms).
- Repositionnable.
- `noteColorClass(slug)` → `--note-hue` → couleur du papier.

### 8.6 People (CRM léger)

#### People Browser (`/people`)

- **Search** : name / company / role / email / tags.
- **Filter chips** : All / Favorites / Due follow-up.
- **Table** : Person (avatar + name) / Company / Tags / Last contact (relative) / Follow-up (badge) / ★ (favorite toggle).
- **FollowUpBadge** : overdue → danger, due today → warn, else → relative day.
- **Row click** → person profile.
- **Star toggle** : `toggleFavorite`.
- **Dialog auto-open** si `?new=1`.

#### Person Detail (`/people/:id`)

- **Left aside** :
  - Avatar (initiales, hue déterministe).
  - Name, role · company.
  - Tags.
  - Contact links : mailto (email), tel (phone) → sur macOS : `NSWorkspace.open(URL)` pour `mailto:` et `tel:`.
  - Last contacted date.
  - Follow-up date picker (Set / Mark done).
  - Edit / Delete buttons.
- **Right** :
  - **"Log an interaction" card** :
    - Kind selector : Note / Call / Meeting / Message / Email (chacun avec une icône).
    - Textarea (⌘+Enter pour sauver).
    - Date picker (max = today).
    - "Log it" button.
  - **Timeline** :
    - Verticale avec ligne de connexion.
    - Chaque entrée : icône (kind), label, date, relative day, note text.
    - Delete au survol.
    - Ajouter une interaction met à jour `lastContactedAt` si la date est plus récente.

#### Contact Dialog (create / edit)

- **Fields** : Name, Role, Company, Email, Phone, Tags (comma-separated), Next follow-up (date picker).

### 8.7 Settings (`/settings`)

#### Profile

- **Name** : input + Save. Utilisé dans le greeting de la home.

#### Appearance

- **Theme picker** : 3 cartes (Light / Dark / System) avec icônes.
- **Accent picker** : 8 presets + custom color picker (`ColorPicker` SwiftUI).
- **Application instantanée** : applique immédiatement sur l'UI (thème + accent), puis persiste via `saveSettings`.

#### Data

- **Counts grid** : Habits, Check-ins, Ideas, People, Interactions (avec compteurs live).
- **Export JSON** : lien de téléchargement → génère un fichier `orbit-export-YYYY-MM-DD.json` (voir §12).
- **Erase all data** : bouton danger → confirm dialog → `wipeAllData` (supprime tout sauf settings).

#### About

- Version (1.0.0).
- Note sur le stockage local.
- Mention de la roadmap (Pixel mascot, markdown rendering, reminders).

---

## 9. Algorithmes et logique métier clés

### 9.1 Streak calculation (`calcStreaks`)

```swift
func calcStreaks(dates: Set<String>) -> (current: Int, best: Int) {
    // best = plus longue série de jours consécutifs
    // current = à partir d'aujourd'hui (ou hier), remonter tant que le jour existe
    
    let sorted = dates.sorted()
    var best = 0, current = 0, run = 0
    var prev: Date? = nil
    for dateStr in sorted {
        let d = parseISO(dateStr)
        if let p = prev, Calendar.current.dateComponents([.day], from: p, to: d).day == 1 {
            run += 1
        } else {
            run = 1
        }
        best = max(best, run)
        prev = d
    }
    
    // current : walk back from today
    let today = Calendar.current.startOfDay(for: Date())
    let checkStart = dates.contains(iso(today)) ? today 
        : Calendar.current.date(byAdding: .day, value: -1, to: today)!
    current = 0
    var cursor = checkStart
    while dates.contains(iso(cursor)) {
        current += 1
        cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)!
    }
    
    return (current, best)
}
```

### 9.2 Heatmap week building (`buildWeeks`)

- **Monday-first** : aligner le `from` sur le lundi de sa semaine.
- Générer des `Week` de 7 slots (null pour hors range).
- **Month labels** : espacés d'au moins 3 semaines pour éviter la surcharge.
- Day labels : Mon / Wed / Fri (2 lettres).

### 9.3 Heatmap level thresholds

- **Home activity** : `[1, 2, 4, 6]` → niveau 1 si count ≥ 1, niveau 2 si ≥ 2, niveau 3 si ≥ 4, niveau 4 si ≥ 6.
- **Per-habit** : `[1, 1, 1, 1]` → binaire, n'importe quel check-in = niveau 4 (max).

### 9.4 Task completion roll-up (`recomputeTask`)

Voir §8.4. Points clés :
- Map parent → enfants.
- `isComplete` récursif avec memoization.
- Composite done ⟺ tous les descendants done.
- Task done ⟺ toutes les steps top-level done.
- Persister les états dérivés + set/clear `completedAt`.
- Déclenché après **toute** mutation de step.

### 9.5 Composite step protection

`toggleStep` ignore les toggles directs sur les steps qui ont des enfants. Seules les **leaves** sont toggglables. L'état des composites est toujours dérivé.

### 9.6 Idea link normalization

Paires stockées comme `(min(A, B), max(A, B))` par comparaison d'UUID string. L'unique index catching les dupes quelle que soit la direction du drag.

### 9.7 Idea merge

- `overlapRatio` : fraction de l'aire du node dragged qui recouvre l'autre. Merge déclenché uniquement si top hit > 0.5 **et** exactement un node a été dragged.
- `mergeIdeas(keepId, mergeId, merged)` :
  1. Update le survivant avec `merged` (title, content, tags).
  2. Re-pointer tous les liens du merge vers le survivant, dédupliquer contre les liens existants du survivant, dropper le lien direct keep↔merge.
  3. Delete le merge (cascade nettoie les anciens liens).

### 9.8 Floating edge geometry

- `borderPoint` : calcule où la ligne centre-à-centre sort du rectangle du node (min de half-width/|dx| et half-height/|dy|).
- `side` : détermine le côté de sortie selon l'axe dominant relatif à l'aspect ratio.
- Border-to-border, indépendant du handle qui a créé le lien.

### 9.9 Auto-tiling

- Nodes non placés (x/y nil) → disposés en grille sous le node placé le plus bas.
- Positions persistées une fois (guard `tiledPersisted` pour ne pas re-tiler).

### 9.10 Pen stroke point filtering

Distance minimale au carré de 4 entre points enregistrés (espace canvas / flow coords). Réduit les points redondants.

### 9.11 Autosave debounces

| Contexte | Délai |
|---|---|
| Idea editor (title/content/tags) | 700ms |
| Task title | 600ms |
| Workflow step title | 500ms |
| Note text | 500ms |

### 9.12 Hue déterministe pour avatars (`hueFromString`)

```swift
func hueFromString(_ s: String) -> Double {
    var hash = 0
    for char in s.unicodeScalars {
        hash = (hash * 31 + Int(char.value)) % 360
    }
    return Double(hash)
}
// Couleur : oklch(lightness=0.72, chroma=0.12, hue=hueFromString(name))
// Background + foreground contrastés
```

### 9.13 Accent scoping

Sur le web : classe CSS `.accent-scope` + inline `--accent` override. Sur macOS : passer la couleur d'accent en paramètre aux sous-vues (heatmap, badges, progress ring). Ne pas modifier une variable globale temporairement.

### 9.14 Habit seed simulation (pour le seed initial)

Génération probabiliste de logs sur ~320 jours :
- Base rate par habitude.
- Weekend modifier.
- **Momentum** : streaks breed streaks (+0.35 sur hit, −0.5 sur miss, clampé 0–1).

---

## 10. Command palette et raccourcis clavier

### 10.1 Command palette (`⌘K`)

- **Trigger** : `⌘K` ou `Ctrl+K` partout, ou event `orbit:command` (bouton Search de la sidebar).
- **Largeur** : 560px, position top 16% (centered horizontalement).
- **Recherche fuzzy** via cmdk (sur macOS : filtrer avec `localizedStandardContains`).
- **Groupes :**

| Groupe | Items |
|---|---|
| **Go to** | Home, Habits, Ideas, Canvas, Tasks, People, Settings (7 pages) |
| **Actions** | New idea, New task, New person, Export data |
| **Log today** | Chaque habitude (avec indicateur check/circle) — toggle le log du jour |
| **Ideas** | Top 8 idées (navigation vers l'éditeur) |
| **People** | Tous les contacts (navigation vers le profil) |

- **En-têtes** : majuscules, 11px, tracking-wider.
- Sur macOS : implémenter avec un `Sheet` contenant un `TextField` + `List` filtrée. Binder `⌘K` via `.keyboardShortcut` ou `NSEvent` monitor.

### 10.2 Raccourcis clavier

| Raccourci | Action |
|---|---|
| `⌘K` | Ouvrir / fermer la command palette |
| `⌘+Enter` | Log an interaction (dans Person Detail) |
| `Enter` | Soumettre un formulaire / ajouter une step / ajouter un tag |
| `Backspace` | Retirer le dernier tag (input vide) / supprimer le stroke sélectionné |
| `Delete` | Supprimer le stroke / step sélectionné (garde contre la saisie texte) |
| `Double-click` (canvas vide) | Créer un node à la position |
| `Double-click` (node) | Ouvrir l'éditeur / le détail |

---

## 11. Paramètres et préférences

### 11.1 Settings app (SwiftData)

| Clé | Type | Défaut | Description |
|---|---|---|---|
| `name` | String | `""` | Nom d'affichage (greeting home) |
| `accent` | String (hex) | `#3d6df2` | Couleur d'accent |
| `theme` | String | `"light"` | `light` / `dark` / `system` |

### 11.2 Prefs UI (UserDefaults)

| Clé | Type | Défaut | Description |
|---|---|---|---|
| `orbit:sidebar-collapsed` | String | `"0"` | Sidebar repliée |
| `orbit:tasks-mode` | String | `"list"` | Mode d'affichage des tâches |
| `orbit:task-detail-mode` | String | `"steps"` | Mode d'affichage du détail tâche |

---

## 12. Export / Import de données

### 12.1 Export JSON

`GET /api/export` (original) → sur macOS : bouton dans Settings > Data.

**Format du fichier** `orbit-export-YYYY-MM-DD.json` :

```json
{
  "app": "orbit",
  "version": "1.0.0",
  "exportedAt": "2026-07-13T10:30:00.000Z",
  "habits": [...],
  "habitLogs": [...],
  "ideas": [...],
  "ideaLinks": [...],
  "contacts": [...],
  "interactions": [...],
  "tasks": [...],
  "taskSteps": [...],
  "stepLinks": [...],
  "boardNotes": [...],
  "boardStrokes": [...],
  "settings": { "name": "...", "accent": "#...", "theme": "..." }
}
```

Toutes les 12 tables de données + settings. Téléchargement en attachment. Sur macOS : `NSSavePanel` pour choisir l'emplacement.

### 12.2 Wipe all data

Supprime toutes les données **sauf** les settings (name, accent, theme). Confirm dialog obligatoire.

---

## 13. Points critiques et pièges à éviter

### 13.1 Données

- **IDs UUID** : toujours générer via `UUID()`, jamais auto-increment. Les références entre tables utilisent l'UUID.
- **Cascade deletes** : s'assurer que SwiftData gère bien les `onDelete(.cascade)` sur toutes les relations FK. Une habitude supprimée doit supprimer ses logs ; un contact supprimé doit supprimer ses interactions ; une idea supprimée doit supprimer ses liens ; une task supprimée doit supprimer ses steps (récursivement), step_links, notes et strokes.
- **Unique constraints** : `(habitId, date)` sur habit_logs, `(ideaAId, ideaBId)` sur idea_links (normalisé), `(sourceId, targetId)` sur step_links. SwiftData ne supporte pas nativement les unique constraints composites — il faut vérifier en code avant insert.
- **Tags en JSON** : stocker comme `String` (JSON encodé) ou utiliser un transformateur custom. Ne pas créer de table de tags séparée.
- **Points en JSON** : `board_strokes.points` = array de `{x, y}` → encoder en JSON.
- **Dates métier en `YYYY-MM-DD`** : pour habit_logs, interactions, follow-ups. Utiliser un `String` pour faciliter les comparaisons de jours. `createdAt` / `updatedAt` / `completedAt` = `Date` (timestamp).

### 13.2 Canvas

- **Coordonnées en flow space** : les positions des nodes et les points des strokes sont en coordonnées canvas (flow coords), pas en coordonnées écran. Le pan/zoom transforme ces coordonnées à l'affichage.
- **Réconciliation des annotations** : les strokes et notes créés optimistically (temp UUID) doivent être réconciliés avec l'ID réel après save. Utiliser des `Set<UUID>` (`pendingNotes`, `pendingStrokes`) pour tracker ce qui n'est pas encore confirmé.
- **Auto-tiling** : ne re-tiler que les nodes non placés (x/y nil) et seulement une fois (guard `tiledPersisted`). Une fois placé, un node ne doit plus jamais être auto-tilé.
- **Merge overlap** : merge uniquement si `overlapRatio > 0.5` **et** exactement un node dragged. Éviter les merges accidentels multi-sélection.
- **Floating edges** : calculer les points de départ/arrivée au bord du rectangle du node (border-to-border), pas au centre. L'edge doit suivre le côté dominant (horizontal/vertical) selon l'aspect ratio.

### 13.3 Task completion roll-up

- **Toujours appeler `recomputeTask` après** : addStep, toggleStep, deleteStep, moveStep, addSubStep.
- **Ne jamais toggle un composite step directement** : `toggleStep` doit ignorer les steps avec enfants.
- **Memoization** : utiliser un cache `[UUID: Bool]` dans `recomputeTask` pour éviter les recalculs exponentiels sur les arbres profonds.
- **completedAt** : set quand la task passe de not-done → done, clear quand done → not-done.

### 13.4 Performance

- **Heatmap 365 jours** : générer les semaines une fois, ne pas recalculer à chaque render. Sur macOS : `@State` ou `@Observable` computed.
- **Canvas avec beaucoup de nodes** : utiliser `LazyVStack` / virtualisation. Sur macOS, les canvas custom peuvent être lents — envisager `Canvas` (SwiftUI) ou `NSView` pour le rendu des strokes.
- **Debounce autosave** : respecter les délais (700ms idée, 600ms task, 500ms step/note) pour éviter les saves excessifs.

### 13.5 Thème

- **Pas de FOUC** : sur le web, un script inline dans `<head>` détecte `prefers-color-scheme` avant le render. Sur macOS, le thème system suit automatiquement `ColorScheme` — pas de FOUC possible.
- **Accent scoping** : ne pas modifier une couleur globale temporairement. Passer la couleur en paramètre aux sous-vues.

### 13.6 UX

- **Future dates désactivées** dans les heatmaps d'habitudes (on ne peut pas logger le futur).
- **Date picker max today** pour les interactions.
- **Garde contre la saisie** : Delete/Backspace ne supprime les strokes/steps que si on n'est pas en train de taper dans un input.
- **Rollback optimiste** : en cas d'erreur de mutation, restaurer l'état précédent + toast d'erreur.
- **Toasts bottom-right** : ne pas bloquer l'UI, auto-dismiss après ~3s.

---

## 14. Roadmap

Ces features sont **mentionnées mais non implémentées** dans la version source 1.0.0. À inclure comme roadmap future dans l'app macOS :

1. **Markdown rendering dans l'éditeur d'idées** : actuellement l'éditeur est plain text. Ajouter du rendu markdown (titres, listes, code blocks, liens).
2. **Reminders / notifications pour les follow-ups** : notifications natives macOS (`UserNotifications` framework) pour rappeler les follow-ups due.
3. **Pixel mascot** : un compagnon axolotl dans la sidebar (idea mentionnée dans le seed data et Settings > About).

---

## 15. Annexe — Correspondances Web → macOS

### 15.1 Stack

| Web | macOS / Swift |
|---|---|
| Next.js App Router | SwiftUI + `NavigationSplitView` |
| React Server Components | SwiftData `@Query` (reactive) |
| Server Actions | `ModelContext` mutations directes |
| Drizzle ORM | SwiftData (`@Model`, `@Query`, `ModelContainer`) |
| SQLite (`@libsql/client`) | SwiftData (backend SQLite) ou `SQLite.swift` |
| Tailwind CSS v4 | SwiftUI modifiers + `Color` extensions |
| Radix UI (Dialog, Dropdown, Switch) | SwiftUI natif (`Sheet`, `Menu`, `Toggle`) |
| cmdk | Command palette custom (`TextField` + `List`) |
| sonner (toasts) | Toast custom (`ZStack` overlay) |
| lucide-react | **SF Symbols** |
| `@xyflow/react` (React Flow) | Canvas custom SwiftUI (zoom/pan + `ZStack`) |
| date-fns | Foundation (`Date`, `Calendar`, `DateFormatter`) |
| class-variance-authority | Enum + `@ViewBuilder` |
| `crypto.randomUUID()` | `UUID()` |

### 15.2 Icônes lucide → SF Symbols (mapping suggéré)

| lucide | SF Symbol | Usage |
|---|---|---|
| Flame | `flame.fill` | Habits, streaks |
| Lightbulb | `lightbulb.fill` | Ideas |
| Waypoints | `point.3.filled.connected.trianglepath.dotted` | Canvas |
| ListChecks | `checklist` | Tasks |
| Users | `person.2.fill` | People |
| Home | `house.fill` | Home |
| Settings | `gearshape.fill` | Settings |
| Search | `magnifyingglass` | Search |
| Plus | `plus` | Create |
| Check | `checkmark` | Done |
| Pin | `pin.fill` | Pin |
| Trash2 | `trash.fill` | Delete |
| Pencil | `pencil` | Edit |
| Star | `star.fill` | Favorite |
| ArrowRight | `arrow.right` | Navigate |
| Sun | `sun.max.fill` | Light theme |
| Moon | `moon.fill` | Dark theme |
| Target | `target` | Habit icon: target |
| Code | `chevron.left.forwardslash.chevron.right` | Habit icon: code |
| Dumbbell | `figure.strengthtraining.traditional` | Habit icon: workout |
| BookOpen | `book.fill` | Habit icon: read |
| PenLine | `pencil.line` | Habit icon: journal |
| Brain | `brain.head.fill` | Habit icon: brain |
| Droplets | `drop.fill` | Habit icon: water |
| Moon | `moon.fill` | Habit icon: sleep |
| Leaf | `leaf.fill` | Habit icon: nature |
| Guitar | `guitar.fill` | Habit icon: music |
| Camera | `camera.fill` | Habit icon: photo |
| Bike | `bicycle` | Habit icon: bike |
| Heart | `heart.fill` | Habit icon: health |
| Coffee | `cup.and.saucer.fill` | Habit icon: coffee |
| Languages | `character.bubble.fill` | Habit icon: languages |
| Briefcase | `briefcase.fill` | Habit icon: work |
| StickyNote | `note.text` | Board annotation |
| Hand | `hand.draw.fill` | Move mode |
| Undo | `arrow.uturn.backward` | Undo |
| Phone | `phone.fill` | Interaction: call |
| Mail | `envelope.fill` | Interaction: email |
| MessageSquare | `message.fill` | Interaction: message |
| Users (meeting) | `person.3.fill` | Interaction: meeting |
| FileText | `doc.text.fill` | Interaction: note |

### 15.3 Interaction kinds (People)

| Kind | Icône | Label |
|---|---|---|
| `note` | `doc.text.fill` | Note |
| `call` | `phone.fill` | Call |
| `meeting` | `person.3.fill` | Meeting |
| `message` | `message.fill` | Message |
| `email` | `envelope.fill` | Email |

### 15.4 Seed data (pour l'initialisation)

L'app doit inclure un seed idempotent (ne seed que si aucune habitude n'existe) avec :

- **Settings** : name "Adam", accent `#3d6df2`, theme light.
- **4 habitudes** :
  1. "Deep work" — icon `code`, color `accent`
  2. "Workout" — icon `dumbbell`, color `emerald`
  3. "Read 20 pages" — icon `book-open`, color `violet`
  4. "Journal" — icon `pen-line`, color `amber`
  - Chaque habitude : ~320 jours de logs probabilistes (base rate + weekend modifier + momentum).
- **6 idées** : concept mascot Pixel, "consistency beats intensity", "people to talk to", "voice memo app idea", "why personal CRMs fail", notes Atomic Habits. Une épinglée. Avec tags.
- **5 contacts** : Sara Mansouri (Product Designer @ Figma), Yassine Berrada (Engineer @ Stripe), Lina Haddad (PM @ Notion), Marc Dubois (Founder @ null), Nadia El Fassi (Researcher @ INRIA). Avec roles, companies, emails, tags, favorites, follow-ups et interaction logs (meetings, calls, messages, emails, notes).

### 15.5 Command palette — structure des groupes

```
[ ⌘K  Orbit Command ]

  Search...

  GO TO
    ⌂  Home
    🔥 Habits
    💡 Ideas
    ⊕ Canvas
    ☑ Tasks
    👥 People
    ⚙  Settings

  ACTIONS
    +  New idea
    +  New task
    +  New person
    ↓  Export data

  LOG TODAY
    ✓  Deep work        ◯/✓
    ✓  Workout          ◯/✓
    ✓  Read 20 pages    ◯/✓
    ✓  Journal          ◯/✓

  IDEAS
    💡 Pixel — the axolotl companion
    💡 Consistency beats intensity
    💡 People to talk to
    ... (top 8)

  PEOPLE
    👤 Sara Mansouri
    👤 Yassine Berrada
    ... (all)
```

---

## Conclusion

Ce document décrit l'intégralité du projet **Orbit** tel qu'il existe dans sa version web 1.0.0, avec un niveau de détail suffisant pour recréer l'application nativement sur macOS avec Swift / SwiftUI / SwiftData.

**Points clés à retenir pour l'implémentation macOS :**

1. **Local-first, aucune dépendance réseau.** Tout est dans un fichier SQLite (SwiftData) local.
2. **Single-user, pas d'auth.** Le seul "identité" est `settings.name`.
3. **Keyboard-first.** `⌘K` command palette est central.
4. **Une seule couleur d'accent** qui imprègne toute l'UI, configurable par l'utilisateur.
5. **Palette neutre chaude** (crème / charbon brun), pas de gris pur.
6. **Police système** (SF Pro sur macOS).
7. **5 sections** : Habits, Ideas (+ Canvas), Tasks (+ Workflows), People, Settings + Home dashboard.
8. **Canvas spatial** pour les idées (React Flow → canvas custom SwiftUI) et pour les tâches (board + workflow).
9. **Annotations manuscrites** (pen + sticky notes) sur les canvas.
10. **Task completion roll-up** récursif — l'algorithme le plus critique.
11. **Heatmaps GitHub-style** Monday-first avec 5 niveaux.
12. **Optimistic UI** avec rollback sur erreur (moins critique sur macOS synchrone, mais utile pour le canvas).
13. **Export JSON complet** + wipe all data (sauf settings).
14. **Seed data idempotent** pour la première installation.

---

*Document généré pour la recréation d'Orbit sur macOS / Swift.*
*Version source : Orbit 1.0.0 — Next.js 16 + SQLite + Drizzle ORM + Tailwind CSS v4 + React Flow.*
