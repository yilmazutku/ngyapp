const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {onDocumentCreated, onDocumentUpdated} =
require('firebase-functions/v2/firestore');

admin.initializeApp();

// =============================================================================
// ADMIN CONFIGURATION
// =============================================================================
const ADMIN_UIDS = new Set([
  '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
  '9CwKr0S4mDdZB4Wlc8BK4W8qsT42', // Utku
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
