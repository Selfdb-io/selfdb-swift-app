//
//  notification.ts
//  Self-Social



// Actual functions

// @ts-nocheck
// deno-lint-ignore-file

export const description = "Send push notifications for new posts, likes, and comments";

export const triggers = [
  {
    type: "database",
    table: "posts",
    operations: ["INSERT"],
    channel: "posts_changes"
  },
  {
    type: "database",
    table: "likes",
    operations: ["INSERT"],
    channel: "likes_changes"
  },
  {
    type: "database",
    table: "comments",
    operations: ["INSERT"],
    channel: "comments_changes"
  }
];

// ─────────────────────────────────────────────────────────────────────────────
// APNS Helper with Token Caching
// ─────────────────────────────────────────────────────────────────────────────

// Cache for APNS JWT token (valid for ~1 hour, we refresh every 50 minutes)
let cachedApnsToken: string | null = null;
let tokenCreatedAt: number = 0;
const TOKEN_REFRESH_INTERVAL = 50 * 60 * 1000; // 50 minutes in ms

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = pem.substring(
    pem.indexOf(pemHeader) + pemHeader.length,
    pem.indexOf(pemFooter)
  );
  const b64 = pemContents.replace(/\s/g, "");
  const binaryString = atob(b64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

async function getApnsToken(env: Record<string, string>): Promise<string> {
  const now = Date.now();
  
  // Return cached token if still valid
  if (cachedApnsToken && (now - tokenCreatedAt) < TOKEN_REFRESH_INTERVAL) {
    return cachedApnsToken;
  }
  
  // Create new token
  const { create } = await import("https://deno.land/x/djwt@v3.0.1/mod.ts");
  
  const keyData = pemToArrayBuffer(env.APNS_KEY_P8);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"]
  );

  const header = { alg: "ES256", kid: env.APNS_KEY_ID };
  const claims = { iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) };
  
  cachedApnsToken = await create(header, claims, key);
  tokenCreatedAt = now;
  
  return cachedApnsToken;
}

async function sendAPNS(
  deviceToken: string,
  payload: Record<string, unknown>,
  env: Record<string, string>
): Promise<{ success: boolean; status: number; response: string }> {
  const token = await getApnsToken(env);
  const apnsUrl = `https://api.sandbox.push.apple.com/3/device/${deviceToken}`;

  const response = await fetch(apnsUrl, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": env.APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const responseText = await response.text();
  
  // If token expired, invalidate cache and retry once
  if (response.status === 403 && responseText.includes("ExpiredProviderToken")) {
    cachedApnsToken = null;
    tokenCreatedAt = 0;
    const newToken = await getApnsToken(env);
    const retryResponse = await fetch(apnsUrl, {
      method: "POST",
      headers: {
        authorization: `bearer ${newToken}`,
        "apns-topic": env.APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    const retryText = await retryResponse.text();
    return { success: retryResponse.status === 200, status: retryResponse.status, response: retryText };
  }
  
  return { success: response.status === 200, status: response.status, response: responseText };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Handler
// ─────────────────────────────────────────────────────────────────────────────

export default async function handler(
  request: Request,
  { env }: { env: Record<string, string> }
) {
  const executionId = Math.random().toString(36).substring(2, 8);
  console.log(`[${executionId}] 📬 Notification handler`);

  try {
    const payload = await request.json();
    const { operation, table, data, old_data } = payload;

    console.log(`[${executionId}] Database trigger: ${operation} on ${table}`);

    // Only handle INSERT operations
    if (operation !== "INSERT") {
      return { success: true, skipped: true, message: `Skipping ${operation}` };
    }

    // Import config from the functions runtime
    const { config } = await import("./config.ts");
    const postgres = await import("https://deno.land/x/postgresjs@v3.4.5/mod.js");
    
    const sql = postgres.default({
      user: config.postgres.user,
      password: config.postgres.password,
      database: config.postgres.database,
      host: config.postgres.host,
      port: config.postgres.port,
    });

    try {
      // Route to appropriate handler based on table
      switch (table) {
        case "posts":
          return await handleNewPost(sql, data, env, executionId);
        case "likes":
          return await handleNewLike(sql, data, env, executionId);
        case "comments":
          return await handleNewComment(sql, data, env, executionId);
        default:
          return { success: true, skipped: true, message: `Unknown table: ${table}` };
      }
    } finally {
      await sql.end();
    }
  } catch (error) {
    console.error(`[${executionId}] ❌ Error:`, error);
    return { success: false, error: error.message };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Post Handler
// ─────────────────────────────────────────────────────────────────────────────

async function handleNewPost(
  sql: any,
  data: any,
  env: Record<string, string>,
  executionId: string
) {
  const { id: postId, user_id: authorId, description: postDescription } = data;
  console.log(`[${executionId}] 📝 New post ${postId} by ${authorId}`);

  // Get author name
  const [author] = await sql`SELECT first_name, last_name FROM users WHERE id = ${authorId}`;
  const authorName = author?.first_name
    ? `${author.first_name}${author.last_name ? ' ' + author.last_name : ''}`
    : "Someone";

  // Get all users except author to create notifications for
  const otherUsers = await sql`SELECT id FROM users WHERE id != ${authorId}`;
  
  if (otherUsers.length === 0) {
    console.log(`[${executionId}] No other users to notify`);
    return { success: true, message: "No other users" };
  }

  const title = `${authorName} posted`;
  const body = postDescription?.substring(0, 100) || "Check out their new post!";
  const notifiedUsers = new Set<string>();
  let pushSent = 0;
  let entriesCreated = 0;

  // Create notification entries for ALL other users
  for (const { id: userId } of otherUsers) {
    await sql`
      INSERT INTO notifications (user_id, sender_id, type, post_id, title, body)
      VALUES (${userId}, ${authorId}, 'new_post', ${postId}, ${title}, ${body})
    `;
    entriesCreated++;
    notifiedUsers.add(userId);
  }

  // Get device tokens for all other users and send push notifications
  const devices = await sql`
    SELECT user_id, device_token FROM device_tokens 
    WHERE user_id != ${authorId} AND platform = 'ios'
  `;

  if (devices.length === 0) {
    console.log(`[${executionId}] ℹ️ No devices registered for push, but ${entriesCreated} notification entries created`);
  } else {
    for (const { user_id, device_token } of devices) {
      const result = await sendAPNS(device_token, {
        aps: { alert: { title, body }, badge: 1, sound: "default" },
        post_id: postId,
        notification_type: "new_post"
      }, env);

      if (result.success) {
        pushSent++;
      } else {
        console.log(`[${executionId}] ⚠️ APNS failed for ${user_id}: ${result.status} ${result.response}`);
      }
    }
  }

  console.log(`[${executionId}] ✅ Created ${entriesCreated} notifications, sent ${pushSent} push`);
  return { success: true, type: "new_post", entriesCreated, pushSent };
}

// ─────────────────────────────────────────────────────────────────────────────
// Like Handler
// ─────────────────────────────────────────────────────────────────────────────

async function handleNewLike(
  sql: any,
  data: any,
  env: Record<string, string>,
  executionId: string
) {
  const { id: likeId, post_id: postId, user_id: likerId } = data;
  console.log(`[${executionId}] ❤️ New like on post ${postId} by ${likerId}`);

  // Get post owner
  const [post] = await sql`SELECT user_id FROM posts WHERE id = ${postId}`;
  if (!post) {
    console.log(`[${executionId}] Post ${postId} not found`);
    return { success: true, skipped: true, message: "Post not found" };
  }
  const ownerId = post.user_id;

  // Don't notify if user liked their own post
  if (ownerId === likerId) {
    console.log(`[${executionId}] Skipping: user liked their own post`);
    return { success: true, skipped: true, message: "User liked own post" };
  }

  // Get liker name
  const [liker] = await sql`SELECT first_name, last_name FROM users WHERE id = ${likerId}`;
  const likerName = liker?.first_name
    ? `${liker.first_name}${liker.last_name ? ' ' + liker.last_name : ''}`
    : "Someone";

  const title = `${likerName} liked your post`;
  const body = "Tap to view your post";

  // Always create notification entry first
  await sql`
    INSERT INTO notifications (user_id, sender_id, type, post_id, title, body)
    VALUES (${ownerId}, ${likerId}, 'like', ${postId}, ${title}, ${body})
  `;
  console.log(`[${executionId}] Created notification entry for ${ownerId}`);

  // Get owner's device tokens and try to send push
  const devices = await sql`
    SELECT device_token FROM device_tokens 
    WHERE user_id = ${ownerId} AND platform = 'ios'
  `;

  let pushSent = 0;
  if (devices.length === 0) {
    console.log(`[${executionId}] ℹ️ Post owner ${ownerId} has no registered devices`);
  } else {
    for (const { device_token } of devices) {
      const result = await sendAPNS(device_token, {
        aps: { alert: { title, body }, badge: 1, sound: "default" },
        post_id: postId,
        notification_type: "like"
      }, env);

      if (result.success) {
        pushSent++;
      } else {
        console.log(`[${executionId}] ⚠️ APNS failed: ${result.status} ${result.response}`);
      }
    }
  }

  console.log(`[${executionId}] ✅ Like notification: entry created, ${pushSent} push sent`);
  return { success: true, type: "like", entryCreated: true, pushSent };
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment Handler
// ─────────────────────────────────────────────────────────────────────────────

async function handleNewComment(
  sql: any,
  data: any,
  env: Record<string, string>,
  executionId: string
) {
  const { id: commentId, post_id: postId, user_id: commenterId, content } = data;
  console.log(`[${executionId}] 💬 New comment on post ${postId} by ${commenterId}`);

  // Get post owner
  const [post] = await sql`SELECT user_id FROM posts WHERE id = ${postId}`;
  if (!post) {
    console.log(`[${executionId}] Post ${postId} not found`);
    return { success: true, skipped: true, message: "Post not found" };
  }
  const ownerId = post.user_id;

  // Don't notify if user commented on their own post
  if (ownerId === commenterId) {
    console.log(`[${executionId}] Skipping: user commented on their own post`);
    return { success: true, skipped: true, message: "User commented on own post" };
  }

  // Get commenter name
  const [commenter] = await sql`SELECT first_name, last_name FROM users WHERE id = ${commenterId}`;
  const commenterName = commenter?.first_name
    ? `${commenter.first_name}${commenter.last_name ? ' ' + commenter.last_name : ''}`
    : "Someone";

  const title = `${commenterName} commented on your post`;
  const body = content?.substring(0, 100) || "Tap to view the comment";

  // Always create notification entry first
  await sql`
    INSERT INTO notifications (user_id, sender_id, type, post_id, comment_id, title, body)
    VALUES (${ownerId}, ${commenterId}, 'comment', ${postId}, ${commentId}, ${title}, ${body})
  `;
  console.log(`[${executionId}] Created notification entry for ${ownerId}`);

  // Get owner's device tokens and try to send push
  const devices = await sql`
    SELECT device_token FROM device_tokens 
    WHERE user_id = ${ownerId} AND platform = 'ios'
  `;

  let pushSent = 0;
  if (devices.length === 0) {
    console.log(`[${executionId}] ℹ️ Post owner ${ownerId} has no registered devices`);
  } else {
    for (const { device_token } of devices) {
      const result = await sendAPNS(device_token, {
        aps: { alert: { title, body }, badge: 1, sound: "default" },
        post_id: postId,
        comment_id: commentId,
        notification_type: "comment"
      }, env);

      if (result.success) {
        pushSent++;
      } else {
        console.log(`[${executionId}] ⚠️ APNS failed: ${result.status} ${result.response}`);
      }
    }
  }

  console.log(`[${executionId}] ✅ Comment notification: entry created, ${pushSent} push sent`);
  return { success: true, type: "comment", entryCreated: true, pushSent };
}
