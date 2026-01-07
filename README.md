# Self‑Social (SelfDB Sample iOS App)

Self‑Social is a sample SwiftUI iOS app that demonstrates how to use the **SelfDB iOS SDK** for:

- Email/password auth (register, login, refresh, logout)
- Creating posts with image/video uploads
- Editing + deleting posts (including media re-ordering)
- Likes (toggle like)
- Comments (CRUD)
- Device token registration
- In-app notifications + APNS push notifications via a SelfDB Function

This repo is meant as a reference implementation, not a production template.

---

## Requirements

- Xcode (recent version)
- A running SelfDB instance + access to the SelfDB Admin Dashboard
- Apple Developer account (for APNS keys)

---

## 1) Configure SelfDB connection

**IMPORTANT:** Before running the app, you must update the connection settings in **SelfDBManager.swift** with your own values:

- **Base URL**: Replace `http://localhost:8000` with your SelfDB instance URL
- **API key**: Replace `selfdb-your-api-key-here` with your actual SelfDB API key

These values are hardcoded in `SelfDBManager.swift` and must be updated to connect to your SelfDB instance.

---

## 2) Create the database tables (required)

Before using the app, you must create the tables in the SelfDB Admin Dashboard.

1. Open **SelfDB Admin Dashboard**
2. Go to **SQL Editor**
3. Paste and run the SQL from:

- `Self-Social/tables.sql`

This creates all required tables and indexes:

- `posts`
- `post_files`
- `likes`
- `comments`
- `device_tokens`
- `notifications`

---

## 3) Set up push notifications (SelfDB Function)

This project includes a SelfDB Function that sends APNS push notifications when:

- a new post is created
- a like is created
- a comment is created

The function code is in:

- `Self-Social/notification.ts`

### 3.1 Important: disable SelfDB realtime notify for Functions table

SelfDB realtime restricts the notify payload size to **~8000 KB**.

Because the Function definition and env payload can exceed the realtime notify payload limit, you may be unable to save your function in the dashboard unless realtime notifications for the `functions` table are disabled.

Run this SQL in the **SelfDB Admin Dashboard → SQL Editor** **before saving** the notification function:

```sql
DROP TRIGGER functions_realtime_notify ON functions;
```

### 3.2 Create the function in SelfDB

1. Open **SelfDB Admin Dashboard**
2. Go to **Functions**
3. Create a new function and paste the contents of `notification.ts`

The function defines database triggers for:

- `posts` INSERT
- `likes` INSERT
- `comments` INSERT

It inserts rows into the `notifications` table and attempts to send push notifications to registered iOS devices using APNS.

---

## 4) APNS env vars you must set

The `notification.ts` function expects these environment variables:

- `APNS_KEY_ID`
- `APNS_KEY_P8`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`

You’ll set these in the SelfDB Functions environment configuration (where SelfDB stores function env vars).

### 4.1 How to get these values from Apple Developer

#### `APNS_BUNDLE_ID`
- This is your app’s Bundle Identifier (e.g. `com.yourcompany.Self-Social`).
- In Xcode: select the project → target → **General** → **Bundle Identifier**.
- In Apple Developer: it must match your registered App ID.

#### `APNS_TEAM_ID`
- Go to Apple Developer account → **Membership**.
- Copy the **Team ID**.

#### `APNS_KEY_ID` + `APNS_KEY_P8`
1. Go to Apple Developer → **Certificates, Identifiers & Profiles**
2. Go to **Keys**
3. Create a new key (enable **Apple Push Notifications service (APNs)**)
4. Download the `.p8` file once (Apple only lets you download it one time)
5. The **Key ID** shown in the portal is your `APNS_KEY_ID`
6. The contents of the downloaded `.p8` file (including the header/footer) are your `APNS_KEY_P8`

Example format for `APNS_KEY_P8`:

```txt
-----BEGIN PRIVATE KEY-----
...base64 key...
-----END PRIVATE KEY-----
```

### 4.2 Sandbox vs Production

`notification.ts` currently posts to the **APNS sandbox** endpoint:

- `https://api.sandbox.push.apple.com/3/device/<token>`

Use sandbox tokens for debug builds. For production/TestFlight, you’ll typically switch to the production endpoint:

- `https://api.push.apple.com/3/device/<token>`

---

## App behavior / features (from `SelfDBManager.swift`)

All SelfDB operations are centralized in `SelfDBManager`, which is an `ObservableObject` used by the SwiftUI views.

### Authentication

- Initializes auth state on launch (`initializeAuth()`)
  - Reads saved access/refresh tokens from `UserDefaults`
  - Calls `client.auth.me()` to restore session
  - If needed, refreshes the access token using `client.auth.refresh(refreshToken:)`
- Login (`login(email:password:)`)
  - Saves tokens
  - Loads current user
  - Preloads table/bucket IDs
  - Registers device token if available
- Register (`register(email:password:firstName:lastName:)`)
  - Creates a user then logs in
- Logout (`logout()`)
  - Removes device token (if registered)
  - Logs out of auth
  - Clears tokens + cached IDs
  - Clears posts + notifications in memory

### Table & bucket ID caching

To reduce repeated lookups, the manager caches:

- table IDs (`tableId(_:)`)
- bucket IDs (`bucketId(_:)`)

It also preloads IDs (`preloadIds()`) after successful auth.

### Posts feed

- Loads recent posts (`loadPosts()`)
  - Fetches posts sorted by `created_at DESC`
  - Fetches `post_files`, `likes`, `comments`
  - Joins everything into `PostWithDetails`
  - Downloads image data and video thumbnails for display

### Create post with media

- Creates a post row (`createPost(description:mediaItems:)`)
- Uploads each media item to SelfDB Storage bucket `post-media`
- Inserts a record into `post_files` for each upload
- For videos, uploads a thumbnail image too (if available)

### Update post

`updatePost(postId:description:newMediaItems:filesToDelete:reorderedExistingFiles:)` supports:

- Editing the post description
- Deleting selected existing media (removes storage files + deletes `post_files` rows)
- Reordering existing media (`display_order` updates)
- Uploading new media and appending after existing items

### Delete post

`deletePost(_:)`:

- Deletes associated storage files for that post
- Deletes the post row (cascades delete via FK constraints)

### Likes

`toggleLike(postId:)`:

- Optimistically updates UI state (`likesCount`, `userHasLiked`)
- Inserts a like if not liked
- Deletes the like if already liked
- Rolls back local changes on failure

### Comments

- Loads comments for a post (`loadComments(postId:)`)
  - Sorts by `createdAt DESC`
  - Fetches author names from users table
- Adds a comment (`addComment(postId:content:)`)
  - Inserts into `comments`
  - Updates local `commentsCount`
- Updates a comment (`updateComment(commentId:content:)`)
- Deletes a comment (`deleteComment(commentId:postId:)`)
  - Updates local `commentsCount`

### File download helper

`downloadFile(url:)`:

- Extracts the storage path from a `file_url` / `thumbnail_url`
- Downloads bytes via `client.storage.files.download(bucketName:path:)`

### Device tokens

- Registers a device token (`registerDeviceToken(_:)`)
  - Upserts into `device_tokens` (unique constraint on token)
- Removes a device token (`removeDeviceToken(_:)`)

### Notifications (in-app)

- Loads notifications (`loadNotifications()`)
  - Fetches recent rows from `notifications`
  - Filters to the current user
  - Computes unread count
- Marks a single notification read (`markNotificationAsRead(_:)`)
- Marks all read (`markAllNotificationsAsRead()`)

---

## Notes / tips

- Make sure the storage bucket exists in SelfDB:
  - Bucket name expected: `post-media`
- APNS pushes will only send if:
  - the device token exists in `device_tokens`
  - the user has allowed notifications
  - your APNS credentials are correct

---

## Security reminder

Do not commit real APNS private keys to public repos.
Store secrets using SelfDB’s function environment variables instead of hardcoding them.
