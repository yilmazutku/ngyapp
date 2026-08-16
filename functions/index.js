const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} =
require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');

admin.initializeApp();

// =============================================================================
// ADMIN CONFIGURATION
// =============================================================================
const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  'SdPI69ChOvepuq9HrlW6no9rMRn1', // Admin
]);

// =============================================================================
// NOTIFICATION CHANNELS (must match Android string.xml notification_channel_id)
// =============================================================================
const CHAT_CHANNEL_ID = 'chat_messages_v2';
const NEWS_CHANNEL_ID = 'news_announcements';

// =============================================================================
// CHAT NOTIFICATION CONSTANTS
// To change chat notification texts, modify these values:
// =============================================================================

/** Title for admin-to-user chat notifications */
const CHAT_ADMIN_TO_USER_TITLE = 'Nilay Göktepe Yılmaz';

/** Default body when message text is empty */
const CHAT_DEFAULT_BODY = 'Yeni mesaj';

/** Body for image messages */
const CHAT_IMAGE_BODY = 'Fotoğraf';

/**
 * Body template for admin reaction notifications.
 * {emoji} is replaced with the reaction that was left (e.g. '👍').
 * Rendered as e.g. "bir mesajınıza 👍 ifadesi bıraktı".
 */
const CHAT_REACTION_BODY_TEMPLATE = 'bir mesajınıza {emoji} ifadesi bıraktı';

/** Default title for user-to-admin notifications (when user name not found) */
const CHAT_USER_TO_ADMIN_DEFAULT_TITLE = 'Kullanıcı mesajı';

/** Android notification icon (in drawable resources) */
const CHAT_ANDROID_ICON = 'ic_notification';

/** Android notification color (hex) - WhatsApp green */
const CHAT_ANDROID_COLOR = '#075E54';

// =============================================================================
// NEWS NOTIFICATION CONSTANTS
// To change news notification texts, modify these values:
// =============================================================================

/** Emoji prefix for news notification titles */
const NEWS_TITLE_PREFIX = '📢 ';

/** Default title when news document has no title */
const NEWS_DEFAULT_TITLE = 'Yeni Duyuru';

/** Android notification icon for news (in drawable resources) */
const NEWS_ANDROID_ICON = 'ic_notification';

/** Android notification color (hex) - Blue */
const NEWS_ANDROID_COLOR = '#1976D2';

/**
 * Truncate a string for notification bodies.
 * @param {string} str Input string.
 * @param {number} maxLen Max length.
 * @return {string} Truncated string.
 */
function truncate(str, maxLen) {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

/**
 * Build Android notification config with action buttons.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfig(title, body) {
  return {
    priority: 'high', // Delivery priority
    notification: {
      channelId: CHAT_CHANNEL_ID,
      icon: CHAT_ANDROID_ICON,
      color: CHAT_ANDROID_COLOR,
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_MAX', // enables heads-up notification
    },
  };
}

/**
 * Build iOS (APNs) notification config.
 * @param {string} category Optional notification category for action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfig(category = null) {
  const apsPayload = {
    'sound': 'default',
    'badge': 1,
    'mutable-content': 1,
    'content-available': 1,
  };

  // Add category if provided (for actionable notifications)
  if (category) {
    apsPayload['category'] = category;
  }

  return {
    payload: {
      aps: apsPayload,
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Build iOS (APNs) notification config for news/announcements.
 * Uses 'news' category for potential future action buttons.
 * @return {object} APNs config.
 */
function buildApnsConfigForNews() {
  return {
    payload: {
      aps: {
        'sound': 'default',
        'badge': 1,
        'mutable-content': 1,
        'content-available': 1,
        'category': 'NEWS_CATEGORY', // For future actionable notifications
      },
    },
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
  };
}

/**
 * Sends push notification to the user when an admin sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (receiver).
 */
exports.notifyUserOnAdminMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const chatId = event.params.chatId;
      const senderId = msg.senderId || '';

      // Only notify when ADMIN sends
      if (!ADMIN_UIDS.has(senderId)) return;

      // Don't notify admins
      if (ADMIN_UIDS.has(chatId)) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;

      // Single token per user
      const token = userData?.fcmToken;
      if (!token) return;
      const tokens = [token];

      let body = CHAT_DEFAULT_BODY;
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = CHAT_IMAGE_BODY;
      }

      const title = CHAT_ADMIN_TO_USER_TITLE;
      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Check if token is invalid and remove it
      const response = res.responses[0];
      if (!response.success) {
        const code = (response.error && response.error.code) ?
        response.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        logger.warn('FCM send failed', {code: code});

        if (isInvalid) {
          await admin.firestore()
              .collection('users')
              .doc(chatId)
              .update({fcmToken: admin.firestore.FieldValue.delete()});
          logger.info(`Removed invalid token for user ${chatId}`);
        }
      }
    },
);

/**
 * Sends push notification to admins when a user sends a new message.
 * Path: chats/{chatId}/messages/{messageId}
 * In your model: chatId == user UID (the user who owns the chat).
 */
exports.notifyAdminsOnUserMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const msg = snap.data() || {};
      const userChatId = event.params.chatId; // uid
      const senderId = msg.senderId || '';

      // Only notify admins when USER sends (so skip admin->user messages)
      if (ADMIN_UIDS.has(senderId)) return;

      // Collect admin tokens (single token per admin)
      const tokens = [];
      for (const adminUid of ADMIN_UIDS) {
        const adminDoc = await admin.firestore()
            .collection('users')
            .doc(adminUid)
            .get();

        const adminData = adminDoc.exists ? adminDoc.data() : null;
        if (adminData?.fcmToken) {
          tokens.push(adminData.fcmToken);
        }
      }

      if (tokens.length === 0) return;

      // Notification body
      let body = CHAT_DEFAULT_BODY;
      if (typeof msg.text === 'string' && msg.text.trim().length) {
        body = msg.text.trim();
      } else if (typeof msg.imageUrl === 'string' && msg.imageUrl.length) {
        body = CHAT_IMAGE_BODY;
      }

      // Try to get user's name for better notification title
      let title = CHAT_USER_TO_ADMIN_DEFAULT_TITLE;
      try {
        const senderDoc = await admin.firestore()
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists) {
          const senderData = senderDoc.data();
          const name = senderData.name || '';
          const surname = senderData.surname || '';
          if (name) {
            title = surname ? `${name} ${surname}` : name;
          }
        }
      } catch (e) {
        logger.warn('Could not fetch sender name', {error: e.message});
      }

      const truncatedBody = truncate(body, 80);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: truncatedBody,
        },
        data: {
          type: 'chat_admin',
          chatId: userChatId, // admin-> ChatPage(overrideChatId: chatId)
          senderId: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, truncatedBody),
        apns: buildApnsConfig(),
      });

      // Clean up invalid tokens from admin docs
      const adminUidsArray = Array.from(ADMIN_UIDS);
      for (let i = 0; i < res.responses.length; i++) {
        const response = res.responses[i];
        if (response.success) continue;

        const code = (response.error && response.error.code)?
        response.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        logger.warn('FCM send failed', {code: code});

        if (isInvalid && adminUidsArray[i]) {
          await admin.firestore()
              .collection('users')
              .doc(adminUidsArray[i])
              .update({fcmToken: admin.firestore.FieldValue.delete()});
          logger.info(`Removed invalid token for admin ${adminUidsArray[i]}`);
        }
      }
    },
);

/**
 * Sends a push notification to the user when an admin leaves (or changes) a
 * reaction on one of the user's messages.
 *
 * Reactions are stored on the message document as a map keyed by the reactor's
 * UID: `reactions.<uid> = emoji`. This fires on message UPDATES (message
 * creation is handled by the functions above) and only notifies when a *new or
 * changed* reaction authored by an admin appears on a message the user sent.
 * Removing a reaction does not notify.
 *
 * Path: chats/{chatId}/messages/{messageId}. In our model chatId == user UID
 * (the receiver of the notification).
 */
exports.notifyUserOnAdminReaction = onDocumentUpdated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const before = event.data && event.data.before ?
          event.data.before.data() || {} : {};
      const after = event.data && event.data.after ?
          event.data.after.data() || {} : {};
      const chatId = event.params.chatId;

      // Never notify an admin-owned chat (chatId is the user's UID).
      if (ADMIN_UIDS.has(chatId)) return;

      // Only notify for reactions left on the USER's own messages, so the
      // "bir mesajınıza …" wording is always accurate.
      if ((after.senderId || '') !== chatId) return;

      const beforeReactions =
          (before.reactions && typeof before.reactions === 'object') ?
              before.reactions : {};
      const afterReactions =
          (after.reactions && typeof after.reactions === 'object') ?
              after.reactions : {};

      // Find a newly added or changed reaction authored by an admin.
      let emoji = null;
      for (const [uid, value] of Object.entries(afterReactions)) {
        if (!ADMIN_UIDS.has(uid)) continue; // only admin reactions notify
        if (beforeReactions[uid] === value) continue; // unchanged
        emoji = value; // added or changed
      }

      // Nothing new from an admin (e.g. a removal, or a non-admin reaction).
      if (!emoji) return;

      const userDoc = await admin.firestore()
          .collection('users')
          .doc(chatId)
          .get();

      const userData = userDoc.exists ? userDoc.data() : null;
      const token = userData ? userData.fcmToken : null;
      if (!token) return;

      const title = CHAT_ADMIN_TO_USER_TITLE;
      const body = CHAT_REACTION_BODY_TEMPLATE.replace('{emoji}', emoji);

      const res = await admin.messaging().sendEachForMulticast({
        tokens: [token],
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: 'chat',
          chatId: chatId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: buildAndroidConfig(title, body),
        apns: buildApnsConfig(),
      });

      // Remove the token if FCM reports it is no longer valid.
      const response = res.responses[0];
      if (!response.success) {
        const code = (response.error && response.error.code) ?
            response.error.code : '';
        const isInvalid =
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token';

        logger.warn('FCM reaction send failed', {code: code});

        if (isInvalid) {
          await admin.firestore()
              .collection('users')
              .doc(chatId)
              .update({fcmToken: admin.firestore.FieldValue.delete()});
          logger.info(`Removed invalid token for user ${chatId}`);
        }
      }
    },
);

/**
 * Build Android notification config for news/announcements.
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @return {object} Android notification config.
 */
function buildAndroidConfigForNews(title, body) {
  return {
    priority: 'high',
    notification: {
      channelId: NEWS_CHANNEL_ID,
      icon: NEWS_ANDROID_ICON,
      color: NEWS_ANDROID_COLOR,
      sound: 'default',
      defaultSound: true,
      defaultVibrateTimings: true,
      visibility: 'public',
      notificationCount: 1,
      notificationPriority: 'PRIORITY_HIGH',
    },
  };
}

/**
 * Collects all FCM tokens from all users (including admins).
 * Uses single fcmToken field per user.
 * @param {boolean} checkAnnouncementPreference - If true, only returns tokens
 *   for users who have announcementNotificationsEnabled !== false.
 * @return {Promise<string[]>} Array of FCM tokens.
 */
async function getAllUserTokens(checkAnnouncementPreference = false) {
  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const allTokens = [];

  usersSnapshot.docs.forEach((doc) => {
    const userData = doc.data();
    if (!userData?.fcmToken) return;

    // If checking announcement preference, skip users who disabled it
    if (checkAnnouncementPreference) {
      // Default to true if field doesn't exist (new users get notifications)
      const announcementsEnabled =
          userData.announcementNotificationsEnabled !== false;
      if (!announcementsEnabled) {
        return;
      }
    }

    allTokens.push(userData.fcmToken);
  });

  return allTokens;
}

/**
 * Removes invalid FCM tokens from user documents.
 * Uses single fcmToken field per user.
 * @param {string[]} invalidTokens Array of invalid tokens to remove.
 */
async function removeInvalidTokensFromAllUsers(invalidTokens) {
  if (!invalidTokens.length) return;

  const invalidSet = new Set(invalidTokens);
  const usersSnapshot = await admin.firestore()
      .collection('users')
      .get();

  const batch = admin.firestore().batch();
  let batchCount = 0;

  for (const doc of usersSnapshot.docs) {
    const userData = doc.data();
    if (!userData?.fcmToken) continue;

    // Check if this user's token is invalid
    if (!invalidSet.has(userData.fcmToken)) continue;

    batch.update(doc.ref, {
      fcmToken: admin.firestore.FieldValue.delete(),
    });
    batchCount++;

    // Firestore batches have a limit of 500 operations
    if (batchCount >= 400) {
      await batch.commit();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  logger.info(`Removed ${invalidTokens.length} invalid tokens from users`);
}

/**
 * Sends push notifications to all users when a new news is published.
 * Triggers on news document creation.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsCreated = onDocumentCreated(
    'news/{newsId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newsData = snap.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news is published
      if (!newsData.isPublished) {
        logger.info(`News ${newsId} is not published, skipping notification`);
        return;
      }

      const title = newsData.title || NEWS_DEFAULT_TITLE;
      const body = truncate(newsData.bodyText || '', 100);

      logger.info(`Sending notification for new news: ${title}`);

      // Get tokens only for users who have announcements enabled
      const tokens = await getAllUserTokens(true);
      if (tokens.length === 0) {
        logger.info('No eligible user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices ` +
          `(users with announcements enabled)`);

      // Send notification in batches (FCM limit is 500 per request)
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: NEWS_TITLE_PREFIX + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfigForNews(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News notification sent for: ${newsId}`);
    },
);

/**
 * Sends push notifications when a news is updated to published state.
 * Only triggers if news was previously unpublished and is now published.
 * Path: news/{newsId}
 */
exports.notifyUsersOnNewsPublished = onDocumentUpdated(
    'news/{newsId}',
    async (event) => {
      const beforeData = event.data?.before?.data() || {};
      const afterData = event.data?.after?.data() || {};
      const newsId = event.params.newsId;

      // Only send notification if news just became published
      // (was not published before, is published now)
      const wasDraft = !beforeData.isPublished;
      const isNowPublished = afterData.isPublished === true;

      if (!wasDraft || !isNowPublished) {
        logger.info(`News ${newsId} publish state unchanged, skipping`);
        return;
      }

      const title = afterData.title || NEWS_DEFAULT_TITLE;
      const body = truncate(afterData.bodyText || '', 100);

      logger.info(`Sending notification for newly published news: ${title}`);

      // Get tokens only for users who have announcements enabled
      const tokens = await getAllUserTokens(true);
      if (tokens.length === 0) {
        logger.info('No eligible user tokens found, skipping notification');
        return;
      }

      logger.info(`Sending news notification to ${tokens.length} devices ` +
          `(users with announcements enabled)`);

      // Send notification in batches
      const batchSize = 500;
      const invalidTokens = [];

      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);

        const res = await admin.messaging().sendEachForMulticast({
          tokens: batchTokens,
          notification: {
            title: NEWS_TITLE_PREFIX + title,
            body: body,
          },
          data: {
            type: 'news',
            newsId: newsId,
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: buildAndroidConfigForNews(title, body),
          apns: buildApnsConfigForNews(),
        });

        // Collect invalid tokens
        res.responses.forEach((r, idx) => {
          if (r.success) return;

          const code = (r.error && r.error.code) ? r.error.code : '';
          const isInvalid =
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token';

          if (isInvalid) {
            invalidTokens.push(batchTokens[idx]);
          }
          logger.warn('FCM send failed for news publish', {code: code});
        });

        logger.info(`Batch ${Math.floor(i / batchSize) + 1}: ` +
            `${res.successCount} success, ${res.failureCount} failed`);
      }

      // Clean up invalid tokens
      if (invalidTokens.length > 0) {
        await removeInvalidTokensFromAllUsers(invalidTokens);
      }

      logger.info(`News publish notification sent for: ${newsId}`);
    },
);

// =============================================================================
// ADMIN CALLABLE: UPDATE USER EMAIL
// Changes a user's sign-in email on Firebase Authentication while keeping the
// SAME UID and the SAME password, then keeps the Firestore user document in
// sync. After this runs the user can sign in with the new email using their
// existing password, and the old email can no longer be used to sign in.
// Only admins (see ADMIN_UIDS) may call this.
// =============================================================================

/**
 * Callable function that updates a user's sign-in email in place.
 * Expects data: {uid: string, newEmail: string}.
 * @return {Promise<{success: boolean, email: string}>} Result payload.
 */
exports.updateUserEmail = onCall(async (request) => {
  // 1) Authorize: caller must be a signed-in admin.
  const callerUid = request.auth ? request.auth.uid : null;
  if (!callerUid || !ADMIN_UIDS.has(callerUid)) {
    throw new HttpsError(
        'permission-denied',
        'Bu işlem için yönetici yetkisi gereklidir.',
    );
  }

  // 2) Validate input.
  const data = request.data || {};
  const targetUid = typeof data.uid === 'string' ? data.uid.trim() : '';
  const newEmail = typeof data.newEmail === 'string' ?
      data.newEmail.trim().toLowerCase() : '';

  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'Geçersiz kullanıcı.');
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(newEmail)) {
    throw new HttpsError(
        'invalid-argument',
        'Geçerli bir e-posta adresi giriniz.',
    );
  }

  // Never let an admin account's email be changed through this endpoint.
  if (ADMIN_UIDS.has(targetUid)) {
    throw new HttpsError(
        'permission-denied',
        'Yönetici hesabının e-postası bu işlemle değiştirilemez.',
    );
  }

  try {
    // 3) Change the email on the Auth account. UID and password are untouched.
    await admin.auth().updateUser(targetUid, {
      email: newEmail,
      emailVerified: true,
    });

    // 4) Keep the Firestore user document consistent with Auth.
    await admin.firestore().collection('users').doc(targetUid).set({
      email: newEmail,
      updateDate: admin.firestore.FieldValue.serverTimestamp(),
      updateUser: 'admin',
    }, {merge: true});

    logger.info(`Updated sign-in email for user ${targetUid}`);
    return {success: true, email: newEmail};
  } catch (err) {
    logger.error('updateUserEmail failed', {
      uid: targetUid,
      code: err.code,
      message: err.message,
    });

    if (err.code === 'auth/email-already-exists') {
      throw new HttpsError(
          'already-exists',
          'Bu e-posta adresi başka bir hesap tarafından kullanılıyor.',
      );
    }
    if (err.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'Kullanıcı bulunamadı.');
    }
    if (err.code === 'auth/invalid-email') {
      throw new HttpsError(
          'invalid-argument',
          'Geçerli bir e-posta adresi giriniz.',
      );
    }
    throw new HttpsError(
        'internal',
        'E-posta güncellenirken bir hata oluştu.',
    );
  }
});

// =============================================================================
// ADMIN CALLABLE: DELETE USER ACCOUNT
// Permanently deletes a user and EVERYTHING that belongs to them:
//   - The Firestore users/{uid} document and every subcollection
//     (appointments, payments, subscriptions, measurements + Tanita PDFs,
//     tests/documents, dietLists, meals, dailyData, ...).
//   - The user's chat document chats/{uid} and its messages subcollection.
//   - Every Cloud Storage object under users/{uid}/** (dekont, tests, Tanita
//     PDFs, meal photos, chat photos) and chats/{uid}/** (chat images).
//   - The user's Firebase Authentication account.
// Only admins (see ADMIN_UIDS) may call this, and admin accounts can never be
// deleted through it.
// =============================================================================

/**
 * Callable function that permanently deletes a user and all of their data.
 * Expects data: {uid: string}.
 * @return {Promise<{success: boolean, uid: string}>} Result payload.
 */
exports.deleteUserAccount = onCall(
    {timeoutSeconds: 300, memory: '512MiB'},
    async (request) => {
      // 1) Authorize: caller must be a signed-in admin.
      const callerUid = request.auth ? request.auth.uid : null;
      if (!callerUid || !ADMIN_UIDS.has(callerUid)) {
        throw new HttpsError(
            'permission-denied',
            'Bu işlem için yönetici yetkisi gereklidir.',
        );
      }

      // 2) Validate input.
      const data = request.data || {};
      const targetUid = typeof data.uid === 'string' ? data.uid.trim() : '';
      if (!targetUid) {
        throw new HttpsError('invalid-argument', 'Geçersiz kullanıcı.');
      }

      // 3) Never allow deleting an admin account through this endpoint.
      if (ADMIN_UIDS.has(targetUid)) {
        throw new HttpsError(
            'permission-denied',
            'Yönetici hesabı silinemez.',
        );
      }

      const db = admin.firestore();
      const bucket = admin.storage().bucket();

      try {
        // 4) Delete the Auth account first so the user cannot sign in or write
        // new data while the rest of the cleanup runs. Idempotent: a missing
        // account (e.g. a retried call) is treated as already done.
        try {
          await admin.auth().deleteUser(targetUid);
          logger.info(`Auth account deleted for user ${targetUid}`);
        } catch (err) {
          if (err.code === 'auth/user-not-found') {
            logger.warn(`Auth account already absent for user ${targetUid}`);
          } else {
            throw err;
          }
        }

        // 5) Delete every Storage object owned by the user. All uploads live
        // under these two prefixes. The trailing slash prevents matching other
        // UIDs that merely share this UID as a prefix (e.g. "abc" vs "abcd").
        await Promise.all([
          bucket.deleteFiles({prefix: `users/${targetUid}/`}),
          bucket.deleteFiles({prefix: `chats/${targetUid}/`}),
        ]);
        logger.info(`Storage files deleted for user ${targetUid}`);

        // 6) Recursively delete the Firestore document trees. recursiveDelete
        // removes each document together with every nested subcollection and
        // document beneath it.
        await db.recursiveDelete(db.collection('users').doc(targetUid));
        await db.recursiveDelete(db.collection('chats').doc(targetUid));
        logger.info(`Firestore data deleted for user ${targetUid}`);

        return {success: true, uid: targetUid};
      } catch (err) {
        logger.error('deleteUserAccount failed', {
          uid: targetUid,
          code: err.code,
          message: err.message,
        });
        throw new HttpsError(
            'internal',
            'Kullanıcı silinirken bir hata oluştu.',
        );
      }
    },
);
