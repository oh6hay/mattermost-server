CREATE PROCEDURE MigrateRootMentionCount () BEGIN DECLARE MentionCountRoot_EXIST INT; DECLARE MsgCountRoot_EXIST INT;
SELECT COUNT(*)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Channels'
  AND table_schema = DATABASE()
  AND COLUMN_NAME = 'TotalMsgCountRoot' INTO MsgCountRoot_EXIST;
SELECT COUNT(*)
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ChannelMembers'
  AND table_schema = DATABASE()
  AND COLUMN_NAME = 'MsgCountRoot' INTO MentionCountRoot_EXIST;

SET @preparedStatement =
  (SELECT IF(
               (SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'ChannelMembers'
                  AND table_schema = DATABASE()
                  AND COLUMN_NAME = 'MentionCountRoot') > 0, 'SELECT 1', 'ALTER TABLE ChannelMembers ADD COLUMN MentionCountRoot bigint(20);'));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

UPDATE ChannelMembers
INNER JOIN
  (SELECT ChannelId,
          COALESCE(SUM(UnreadMentions), 0) AS UnreadMentions,
          UserId
   FROM ThreadMemberships
   LEFT JOIN Threads ON ThreadMemberships.PostId = Threads.PostId
   GROUP BY Threads.ChannelId,
            ThreadMemberships.UserId) AS q ON q.ChannelId = ChannelMembers.ChannelId
AND q.UserId = ChannelMembers.UserId
AND ChannelMembers.MentionCount > 0
SET MentionCountRoot = ChannelMembers.MentionCount - q.UnreadMentions;

SET @preparedStatement =
  (SELECT IF(
               (SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'Channels'
                  AND table_schema = DATABASE()
                  AND COLUMN_NAME = 'TotalMsgCountRoot') > 0, 'SELECT 1', 'ALTER TABLE Channels ADD COLUMN TotalMsgCountRoot bigint(20);'));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement =
  (SELECT IF(
               (SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'Channels'
                  AND table_schema = DATABASE()
                  AND COLUMN_NAME = 'LastRootPostAt') > 0, 'SELECT 1', 'ALTER TABLE Channels ADD COLUMN LastRootPostAt bigint(20);'));

PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement =
  (SELECT IF(
               (SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'ChannelMembers'
                  AND table_schema = DATABASE()
                  AND COLUMN_NAME = 'MsgCountRoot') > 0, 'SELECT 1', 'ALTER TABLE ChannelMembers ADD COLUMN MsgCountRoot bigint(20);'));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

IF(MsgCountRoot_EXIST = 0) THEN
UPDATE Channels
INNER JOIN
  (SELECT Channels.Id channelid,
          COALESCE(COUNT(*), 0) newcount,
          COALESCE(MAX(Posts.CreateAt), 0) AS lastpost
   FROM Channels
   LEFT JOIN Posts
   FORCE INDEX (idx_posts_channel_id_update_at) ON Channels.Id = Posts.ChannelId
   WHERE Posts.RootId = ''
   GROUP BY Channels.Id) AS q ON q.channelid = Channels.Id
SET TotalMsgCountRoot = q.newcount,
    LastRootPostAt = q.lastpost;
END IF;

IF(MentionCountRoot_EXIST = 0) THEN
UPDATE ChannelMembers CM
INNER JOIN
  (SELECT TotalMsgCountRoot,
          Id,
          LastRootPostAt
   FROM Channels) AS q ON q.id = CM.ChannelId
AND LastViewedAt >= q.lastrootpostat
SET MsgCountRoot = TotalMsgCountRoot;
END IF;

SET @preparedStatement =
  (SELECT IF(
               (SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_NAME = 'Channels'
                  AND table_schema = DATABASE()
                  AND COLUMN_NAME = 'LastRootPostAt' ) > 0, 'ALTER TABLE Channels DROP COLUMN LastRootPostAt;', 'SELECT 1'));

PREPARE alterIfExists
FROM @preparedStatement;
EXECUTE alterIfExists;
DEALLOCATE PREPARE alterIfExists;

END;

CALL MigrateRootMentionCount ();

DROP PROCEDURE IF EXISTS MigrateRootMentionCount;
