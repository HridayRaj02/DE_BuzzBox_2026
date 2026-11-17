# Normalization

**Project:** Netflix Movie & Series Streaming Database  
**Database:** PostgreSQL 15+

This note explains how we organized the tables in [`sql/01_schema.sql`](../sql/01_schema.sql). We started from the data and relationships the app needs to store, then split information into tables so that the same details do not have to be repeated everywhere.

## First Normal Form (1NF)

A table is in first normal form when each cell holds one value and a row represents one record. Repeating columns such as `genre_1`, `genre_2`, and `genre_3`, or putting a comma-separated list of genres in one column, would make the data harder to query and update.

Our schema stores collections as separate rows instead. Each profile has a row in `profiles`, each episode has a row in `episodes`, and each viewing session has a row in `viewing_activity`. Genres are stored in `genres`; `title_genres` records one title–genre pair per row. Ratings, My List entries, and invoices are also stored as their own records.

The tables use primary keys to identify records. `title_genres`, `ratings`, and `my_list` use a pair of IDs as their key, which also prevents the same association from being added twice. A movie viewing can have a null `episode_id`, since movies do not have episodes.

## Second Normal Form (2NF)

Second normal form builds on 1NF. For a table with a multi-column key, every other column should depend on the entire key, not just one part of it.

This matters for three tables in our schema:

| Table | Key | Other columns | Why they depend on the full key |
|---|---|---|---|
| `title_genres` | (`title_id`, `genre_id`) | None | The row only records that a title has a genre. Title and genre descriptions are kept in their own tables. |
| `ratings` | (`profile_id`, `title_id`) | `rating`, `rated_at` | These describe a particular profile rating a particular title. |
| `my_list` | (`profile_id`, `title_id`) | `added_at` | The timestamp belongs to that profile's addition of that title. |

The other tables use a single-column primary key, so there is no smaller part of the primary key for a column to depend on. `episodes` has a second unique key: (`title_id`, `season_no`, `episode_no`). Episode details describe that position within a series.

## Third Normal Form (3NF)

Third normal form means that non-key details belong to the key of their table, rather than depending on some other non-key detail. In practice, this means keeping each entity's description with that entity and referring to it by ID elsewhere.

For example, an account stores `plan_id`, while the plan name, price, stream limit, resolution, and ad setting live in `plans`. If we copied the plan details into every account row, a price change could require updating many rows. Likewise, `genre_name` is stored in `genres`, not repeated on each title, and profile and title details are not copied into viewing records.

The same idea applies to the other relationships. `profiles` refers to its account; `episodes` refers to its series in `titles`; and `viewing_activity` refers to the profile and title involved in a play. Ratings and My List entries refer to both a profile and a title, with only their own relationship details stored on those rows. An invoice keeps its amount and billing status as facts about that particular billing event.

## Tables in the final schema

| Table | Primary key | What it stores |
|---|---|---|
| `plans` | `plan_id` | Available subscription plans. |
| `accounts` | `account_id` | Account and subscription status. |
| `profiles` | `profile_id` | Profiles belonging to accounts. |
| `genres` | `genre_id` | Genre names. |
| `titles` | `title_id` | Movies and series. |
| `title_genres` | (`title_id`, `genre_id`) | Genres assigned to titles. |
| `episodes` | `episode_id` | Episodes belonging to series. |
| `viewing_activity` | `view_id` | Playback records. |
| `ratings` | (`profile_id`, `title_id`) | A profile's rating of a title. |
| `my_list` | (`profile_id`, `title_id`) | Titles saved by profiles. |
| `invoices` | `invoice_id` | Account billing records. |

Overall, the schema uses separate tables for accounts, plans, profiles, titles, and other entities, and link tables for many-to-many relationships. This avoids repeating groups, keeps composite-key tables dependent on their full keys, and stores descriptive details alongside the entity they describe.
