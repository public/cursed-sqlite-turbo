-- advplyr/audiobookshelf @ edb1f7efc92ecacdef51aafb4d9d5054ce10604f (GPL-3.0)
-- Reconstructed from the Sequelize model definitions (server/models/*.js: Library, User, LibraryItem, Book, Author,
-- BookAuthor, Series, BookSeries, MediaProgress, Podcast, PodcastEpisode, PlaybackSession) as Sequelize v6's SQLite
-- dialect creates them on sync(): UUID text ids, VARCHAR(255) strings, TINYINT(1) booleans, JSON/DATETIME columns,
-- createdAt/updatedAt timestamps, association foreign keys appended, UNIQUE pairs on belongsToMany through models.
-- Indexes from the models' `indexes` options (names as Sequelize derives them) and server/migrations/v2.15.2,
-- v2.17.7, v2.19.1, v2.20.0, v2.33.0. Triggers from server/Database.js addTriggers(). Only what the queries need.

CREATE TABLE `libraries` (`id` UUID PRIMARY KEY, `name` VARCHAR(255), `displayOrder` INTEGER, `icon` VARCHAR(255),
  `mediaType` VARCHAR(255), `provider` VARCHAR(255), `lastScan` DATETIME, `lastScanVersion` VARCHAR(255),
  `settings` JSON, `extraData` JSON, `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL);

CREATE TABLE `users` (`id` UUID PRIMARY KEY, `username` VARCHAR(255), `email` VARCHAR(255), `pash` VARCHAR(255),
  `type` VARCHAR(255), `token` VARCHAR(255), `isActive` TINYINT(1) DEFAULT 0, `isLocked` TINYINT(1) DEFAULT 0,
  `lastSeen` DATETIME, `permissions` JSON, `bookmarks` JSON, `extraData` JSON,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL);

CREATE TABLE `books` (`id` UUID PRIMARY KEY, `title` VARCHAR(255), `titleIgnorePrefix` VARCHAR(255),
  `subtitle` VARCHAR(255), `publishedYear` VARCHAR(255), `publishedDate` VARCHAR(255), `publisher` VARCHAR(255),
  `description` TEXT, `isbn` VARCHAR(255), `asin` VARCHAR(255), `language` VARCHAR(255), `explicit` TINYINT(1),
  `abridged` TINYINT(1), `coverPath` VARCHAR(255), `duration` FLOAT, `narrators` JSON, `audioFiles` JSON,
  `ebookFile` JSON, `chapters` JSON, `tags` JSON, `genres` JSON,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL);
CREATE INDEX `books_title` ON `books` (`title` COLLATE NOCASE);
CREATE INDEX `books_published_year` ON `books` (`publishedYear`);
CREATE INDEX `books_duration` ON `books` (`duration`);

CREATE TABLE `podcasts` (`id` UUID PRIMARY KEY, `title` VARCHAR(255), `titleIgnorePrefix` VARCHAR(255),
  `author` VARCHAR(255), `releaseDate` VARCHAR(255), `feedURL` VARCHAR(255), `imageURL` VARCHAR(255),
  `description` TEXT, `itunesPageURL` VARCHAR(255), `itunesId` VARCHAR(255), `itunesArtistId` VARCHAR(255),
  `language` VARCHAR(255), `podcastType` VARCHAR(255), `explicit` TINYINT(1), `autoDownloadEpisodes` TINYINT(1),
  `autoDownloadSchedule` VARCHAR(255), `lastEpisodeCheck` DATETIME, `maxEpisodesToKeep` INTEGER,
  `maxNewEpisodesToDownload` INTEGER, `coverPath` VARCHAR(255), `tags` JSON, `genres` JSON,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL, `numEpisodes` INTEGER DEFAULT 0);

CREATE TABLE `libraryItems` (`id` UUID PRIMARY KEY, `ino` VARCHAR(255), `path` VARCHAR(255), `relPath` VARCHAR(255),
  `mediaId` UUID, `mediaType` VARCHAR(255), `isFile` TINYINT(1), `isMissing` TINYINT(1), `isInvalid` TINYINT(1),
  `mtime` DATETIME, `ctime` DATETIME, `birthtime` DATETIME, `size` BIGINT, `lastScan` DATETIME,
  `lastScanVersion` VARCHAR(255), `libraryFiles` JSON, `extraData` JSON,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL,
  `libraryId` UUID REFERENCES `libraries` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  `libraryFolderId` UUID,
  `title` VARCHAR(255), `titleIgnorePrefix` VARCHAR(255),
  `authorNamesFirstLast` VARCHAR(255), `authorNamesLastFirst` VARCHAR(255));
CREATE INDEX `library_items_created_at` ON `libraryItems` (`createdAt`);
CREATE INDEX `library_items_media_id` ON `libraryItems` (`mediaId`);
CREATE INDEX `library_items_library_id_media_type` ON `libraryItems` (`libraryId`, `mediaType`);
CREATE INDEX `library_items_library_id_media_type_size` ON `libraryItems` (`libraryId`, `mediaType`, `size`);
CREATE INDEX `library_items_library_id_media_type_created_at` ON `libraryItems` (`libraryId`, `mediaType`, `createdAt`);
CREATE INDEX `library_items_library_id_media_type_title` ON `libraryItems` (`libraryId`, `mediaType`, `title` COLLATE NOCASE);
CREATE INDEX `library_items_library_id_media_type_title_ignore_prefix` ON `libraryItems` (`libraryId`, `mediaType`, `titleIgnorePrefix` COLLATE NOCASE);
CREATE INDEX `library_items_library_id_media_type_author_names_first_last` ON `libraryItems` (`libraryId`, `mediaType`, `authorNamesFirstLast` COLLATE NOCASE);
CREATE INDEX `library_items_library_id_media_type_author_names_last_first` ON `libraryItems` (`libraryId`, `mediaType`, `authorNamesLastFirst` COLLATE NOCASE);
CREATE INDEX `library_items_library_id_media_id_media_type` ON `libraryItems` (`libraryId`, `mediaId`, `mediaType`);
CREATE INDEX `library_items_birthtime` ON `libraryItems` (`birthtime`);
CREATE INDEX `library_items_mtime` ON `libraryItems` (`mtime`);

CREATE TABLE `authors` (`id` UUID PRIMARY KEY, `name` VARCHAR(255), `lastFirst` VARCHAR(255), `asin` VARCHAR(255),
  `description` TEXT, `imagePath` VARCHAR(255), `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL,
  `libraryId` UUID REFERENCES `libraries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `authors_name` ON `authors` (`name` COLLATE NOCASE);
CREATE INDEX `authors_library_id` ON `authors` (`libraryId`);

CREATE TABLE `bookAuthors` (`id` UUID PRIMARY KEY, `createdAt` DATETIME NOT NULL,
  `bookId` UUID REFERENCES `books` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  `authorId` UUID REFERENCES `authors` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE (`bookId`, `authorId`));
CREATE INDEX `bookAuthor_authorId` ON `bookAuthors` (`authorId`);

CREATE TABLE `series` (`id` UUID PRIMARY KEY, `name` VARCHAR(255), `nameIgnorePrefix` VARCHAR(255), `description` TEXT,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL,
  `libraryId` UUID REFERENCES `libraries` (`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `series_name` ON `series` (`name` COLLATE NOCASE);
CREATE UNIQUE INDEX `unique_series_name_per_library` ON `series` (`name`, `libraryId`);
CREATE INDEX `series_library_id` ON `series` (`libraryId`);

CREATE TABLE `bookSeries` (`id` UUID PRIMARY KEY, `sequence` VARCHAR(255), `createdAt` DATETIME NOT NULL,
  `bookId` UUID REFERENCES `books` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  `seriesId` UUID REFERENCES `series` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE (`bookId`, `seriesId`));
CREATE INDEX `bookSeries_seriesId` ON `bookSeries` (`seriesId`);
CREATE INDEX `book_series_series_book` ON `bookSeries` (`seriesId`, `bookId`);

CREATE TABLE `podcastEpisodes` (`id` UUID PRIMARY KEY, `index` INTEGER, `season` VARCHAR(255), `episode` VARCHAR(255),
  `episodeType` VARCHAR(255), `title` VARCHAR(255), `subtitle` VARCHAR(1000), `description` TEXT,
  `pubDate` VARCHAR(255), `enclosureURL` VARCHAR(255), `enclosureSize` BIGINT, `enclosureType` VARCHAR(255),
  `publishedAt` DATETIME, `audioFile` JSON, `chapters` JSON, `extraData` JSON,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL,
  `podcastId` UUID REFERENCES `podcasts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX `podcastEpisode_createdAt_podcastId` ON `podcastEpisodes` (`createdAt`, `podcastId`);
CREATE INDEX `podcast_episodes_published_at` ON `podcastEpisodes` (`publishedAt`);

CREATE TABLE `mediaProgresses` (`id` UUID PRIMARY KEY, `mediaItemId` UUID, `mediaItemType` VARCHAR(255),
  `duration` FLOAT, `currentTime` FLOAT, `isFinished` TINYINT(1), `hideFromContinueListening` TINYINT(1),
  `ebookLocation` VARCHAR(255), `ebookProgress` FLOAT, `finishedAt` DATETIME, `extraData` JSON,
  `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL,
  `userId` UUID REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  `podcastId` UUID);
CREATE INDEX `media_progresses_updated_at` ON `mediaProgresses` (`updatedAt`);
CREATE INDEX `media_progresses_user_item_finished_time` ON `mediaProgresses` (`userId`, `mediaItemId`, `isFinished`, `currentTime`);

CREATE TABLE `playbackSessions` (`id` UUID PRIMARY KEY, `mediaItemId` UUID, `mediaItemType` VARCHAR(255),
  `displayTitle` VARCHAR(255), `displayAuthor` VARCHAR(255), `duration` FLOAT, `playMethod` INTEGER,
  `mediaPlayer` VARCHAR(255), `startTime` FLOAT, `currentTime` FLOAT, `serverVersion` VARCHAR(255),
  `coverPath` VARCHAR(255), `timeListening` INTEGER, `mediaMetadata` JSON, `date` VARCHAR(255),
  `dayOfWeek` VARCHAR(255), `extraData` JSON, `createdAt` DATETIME NOT NULL, `updatedAt` DATETIME NOT NULL,
  `userId` UUID REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  `deviceId` UUID,
  `libraryId` UUID REFERENCES `libraries` (`id`) ON DELETE SET NULL ON UPDATE CASCADE);

-- server/Database.js addTriggers(): keep libraryItems.title/authorNames* in sync with books and bookAuthors
CREATE TRIGGER update_library_items_title
  AFTER UPDATE OF title ON books
  FOR EACH ROW
  BEGIN
    UPDATE libraryItems SET title = NEW.title WHERE libraryItems.mediaId = NEW.id;
  END;

CREATE TRIGGER update_library_items_author_names_on_book_authors_insert
  AFTER insert ON bookAuthors
  FOR EACH ROW
  BEGIN
    UPDATE libraryItems
      SET (authorNamesFirstLast, authorNamesLastFirst) = (
        SELECT GROUP_CONCAT(authors.name, ', ' ORDER BY bookAuthors.createdAt ASC), GROUP_CONCAT(authors.lastFirst, ', ' ORDER BY bookAuthors.createdAt ASC)
        FROM authors JOIN bookAuthors ON authors.id = bookAuthors.authorId
        WHERE bookAuthors.bookId = NEW.bookId
      )
    WHERE mediaId = NEW.bookId;
  END;
