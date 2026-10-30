-- Jellyfin 10.10.7 (jellyfin/jellyfin @ aefb9b2, tag v10.10.7, GPL-2.0). The last release line before the EF Core
-- rewrite: Emby.Server.Implementations/Data/SqliteItemRepository.cs builds the TypedBaseItems SQL by string
-- concatenation (GetItemList/GetItems + SetFinalColumnsToSelect + GetWhereClauses + GetGroupBy + GetOrderByText,
-- GetItemValues for genres/studios/artists). Each item query below is one representative instantiation for a real
-- caller (home screen, resume, next up, library browse, genres, search, similar), tagged dynamic; the column list is
-- the one SetFinalColumnsToSelect leaves for that caller's DtoOptions. Microsoft.Data.Sqlite binds @name params;
-- System.Guid binds as a 16-byte blob, TopParentId/AncestorIdText are "N" hex strings. Users: 1 = admin, 2 = kid.

-- @id jellyfin.latest.movies_library
-- @src Emby.Server.Implementations/Library/UserViewManager.cs:354-374 -> LibraryManager.cs:1328 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (where 2975, order 2809)
-- @style @name params; columns from SetFinalColumnsToSelect, WHERE from GetWhereClauses, joined with AND
-- @tags hotpath,dynamic
-- @note Home 'Latest Movies' row (HidePlayedInLatest): UserDatas left join, unplayed filter, group by PresentationUniqueKey, top 16*5 by DateCreated/SortName/ProductionYear.
-- @param @UserId 1
-- @param @IsFolder 0
-- @param @IsPlayed 0
-- @param @IsVirtualItem 0
-- @param @MediaTypes 'Video'
-- @param @TopParentId '9e377a1200014e379eef000000000001'
select type,data,StartDate,EndDate,ChannelId,IsMovie,IsSeries,EpisodeTitle,IsRepeat,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,ExternalServiceId,IsInMixedFolder,Tags,TrailerTypes,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,ShowId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where IsFolder=@IsFolder
  AND (played is null or played=@IsPlayed)
  AND IsVirtualItem=@IsVirtualItem
  AND MediaType=@MediaTypes
  AND (TopParentId=@TopParentId)
Group by PresentationUniqueKey
ORDER BY DateCreated DESC,SortName DESC,ProductionYear DESC
LIMIT 80;

-- @id jellyfin.latest.all_libraries_kid_profile
-- @src Emby.Server.Implementations/Library/UserViewManager.cs:278-374 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (parental clause 3816, blocked tags 4169-4190)
-- @style @name params; dynamic WHERE incl. per-user parental rating and blocked-tag clauses
-- @tags hotpath,dynamic
-- @note Home 'Latest' across all 4 libraries for a restricted profile: MediaType IN list, TopParentId IN list, max parental rating, correlated blocked-tag probe on ItemValues, grouped top-N.
-- @param @IsFolder 0
-- @param @MaxParentalRating 7
-- @param @IsVirtualItem 0
-- @param @ExcludeInheritedTags0 'gore'
select type,data,StartDate,EndDate,ChannelId,IsMovie,IsSeries,EpisodeTitle,IsRepeat,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,ExternalServiceId,IsInMixedFolder,Tags,TrailerTypes,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,ShowId,OwnerId from TypedBaseItems A
where IsFolder=@IsFolder
  AND (InheritedParentalRatingValue is null OR InheritedParentalRatingValue <= @MaxParentalRating)
  AND IsVirtualItem=@IsVirtualItem
  AND MediaType in ('Video','Audio')
  AND TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004')
  AND ((select CleanValue from ItemValues where ItemId=Guid and Type=6 and cleanvalue in (@ExcludeInheritedTags0)) is null)
Group by PresentationUniqueKey
ORDER BY DateCreated DESC,SortName DESC,ProductionYear DESC
LIMIT 80;

-- @id jellyfin.resume.continue_watching
-- @src Jellyfin.Api/Controllers/ItemsController.cs:874-892 -> LibraryManager.cs:1467 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534
-- @style @name params; dynamic WHERE (IsResumable forces IsVirtualItem=false)
-- @tags hotpath,dynamic
-- @note Home 'Continue Watching': UserDatas join filtered on playbackPositionTicks > 0 across all user views, ordered by LastPlayedDate.
-- @param @UserId 1
-- @param @IsVirtualItem 0
-- @param @MediaTypes 'Video'
select type,data,StartDate,EndDate,ChannelId,IsMovie,IsSeries,EpisodeTitle,IsRepeat,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,ExternalServiceId,IsInMixedFolder,Tags,TrailerTypes,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,ShowId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where playbackPositionTicks > 0
  AND IsVirtualItem=@IsVirtualItem
  AND MediaType=@MediaTypes
  AND TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004')
Group by PresentationUniqueKey
ORDER BY LastPlayedDate DESC
LIMIT 12;

-- @id jellyfin.nextup.recent_series
-- @src Emby.Server.Implementations/TV/TVSeriesManager.cs:101-113 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (GetGroupBy 2416, DatePlayed -> MAX(LastPlayedDate) 2852)
-- @style @name params; GroupBySeriesPresentationUniqueKey, no LIMIT
-- @tags hotpath,dynamic
-- @note Next Up step 1: every episode in the TV libraries grouped by series, ordered by MAX(LastPlayedDate) from the UserDatas join.
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.TV.Episode'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,TotalBitrate,ExtraType,ExternalId,SeriesPresentationUniqueKey,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004')
Group by SeriesPresentationUniqueKey
ORDER BY MAX(LastPlayedDate) DESC;

-- @id jellyfin.nextup.last_watched_episode
-- @src Emby.Server.Implementations/TV/TVSeriesManager.cs:177-197 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534
-- @style @name params; dynamic WHERE
-- @tags hotpath,dynamic
-- @note Next Up step 2, once per series: last played episode by season/episode number desc, LIMIT 1.
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.TV.Episode'
-- @param @ParentIndexNumberNotEquals 0
-- @param @IsPlayed 1
-- @param @SeriesPresentationUniqueKey '17156198000347139aab000000000005'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,ForcedSortName,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,TotalBitrate,ExtraType,ExternalId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND (ParentIndexNumber<>@ParentIndexNumberNotEquals or ParentIndexNumber is null)
  AND (played=@IsPlayed)
  AND SeriesPresentationUniqueKey=@SeriesPresentationUniqueKey
Group by PresentationUniqueKey
ORDER BY ParentIndexNumber DESC,IndexNumber DESC
LIMIT 1;

-- @id jellyfin.nextup.next_episode
-- @src Emby.Server.Implementations/TV/TVSeriesManager.cs:201-222 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534
-- @style @name params; dynamic WHERE (MinParentAndIndexNumber from the last watched episode)
-- @tags hotpath,dynamic
-- @note Next Up step 3, once per series: first unplayed, non-virtual episode after (season, episode), OR-of-ranges predicate.
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.TV.Episode'
-- @param @MinParentAndIndexNumberParent 3
-- @param @MinParentAndIndexNumberIndex 3
-- @param @ParentIndexNumberNotEquals 0
-- @param @IsPlayed 0
-- @param @IsVirtualItem 0
-- @param @SeriesPresentationUniqueKey '17156198000347139aab000000000005'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND ((ParentIndexNumber=@MinParentAndIndexNumberParent and IndexNumber>=@MinParentAndIndexNumberIndex) or ParentIndexNumber>@MinParentAndIndexNumberParent)
  AND (ParentIndexNumber<>@ParentIndexNumberNotEquals or ParentIndexNumber is null)
  AND (played is null or played=@IsPlayed)
  AND IsVirtualItem=@IsVirtualItem
  AND SeriesPresentationUniqueKey=@SeriesPresentationUniqueKey
Group by PresentationUniqueKey
ORDER BY ParentIndexNumber ASC,IndexNumber ASC
LIMIT 1;

-- @id jellyfin.browse.movies_by_name_page2
-- @src Jellyfin.Api/Controllers/ItemsController.cs:160-521 -> LibraryManager.cs:1467 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2640-2700
-- @style @name params; dynamic WHERE, LIMIT/OFFSET appended as literals
-- @tags hotpath,dynamic
-- @note Movies library grid, second page: type + TopParentId, group by PresentationUniqueKey, ORDER BY SortName, ProductionYear with OFFSET.
-- @param @type 'MediaBrowser.Controller.Entities.Movies.Movie'
-- @param @TopParentId '9e377a1200014e379eef000000000001'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId from TypedBaseItems A
where type=@type
  AND (TopParentId=@TopParentId)
Group by PresentationUniqueKey
ORDER BY SortName ASC,ProductionYear ASC
LIMIT 100 OFFSET 100;

-- @id jellyfin.browse.movies_total_count
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:2709-2741
-- @style @name params; same WHERE text as the page query
-- @tags hotpath,dynamic
-- @note TotalRecordCount companion of every paged library grid: count(distinct PresentationUniqueKey) over the same filter.
-- @param @type 'MediaBrowser.Controller.Entities.Movies.Movie'
-- @param @TopParentId '9e377a1200014e379eef000000000001'
select count (distinct PresentationUniqueKey) from TypedBaseItems A
where type=@type
  AND (TopParentId=@TopParentId);

-- @id jellyfin.browse.movies_filtered_unplayed
-- @src Jellyfin.Api/Controllers/ItemsController.cs:160-521 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2640-2700 (genres 3667, ratings 3729, years 3942)
-- @style @name params; dynamic WHERE: one correlated IN-probe per genre OR'ed, rating OR list, literal year IN list
-- @tags hotpath,dynamic
-- @note Movies grid with Unplayed + Genres + Ratings + Years filters, sorted by CommunityRating: correlated ItemValues probes per row plus UserDatas join.
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.Movies.Movie'
-- @param @IsPlayed 0
-- @param @Genre0 'action'
-- @param @Genre1 'science fiction'
-- @param @OfficialRating0 'PG-13'
-- @param @OfficialRating1 'R'
-- @param @TopParentId '9e377a1200014e379eef000000000001'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND (played is null or played=@IsPlayed)
  AND (@Genre0 in (select CleanValue from ItemValues where ItemId=Guid and Type=2) OR @Genre1 in (select CleanValue from ItemValues where ItemId=Guid and Type=2))
  AND (OfficialRating=@OfficialRating0 OR OfficialRating=@OfficialRating1)
  AND ProductionYear in (1980,1981,1982,1983,1984,1985,1986,1987,1988,1989,1990,1991,1992,1993,1994,1995,1996,1997,1998,1999)
  AND (TopParentId=@TopParentId)
Group by PresentationUniqueKey
ORDER BY CommunityRating DESC,SortName ASC
LIMIT 100;

-- @id jellyfin.browse.movies_filtered_count
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:2709-2741
-- @style @name params; SetFinalColumnsToSelect also appends the UserDatas columns to the count query
-- @tags hotpath,dynamic
-- @note Total count for the filtered grid: aggregate plus bare UserDatas columns (SetFinalColumnsToSelect runs on the count list too).
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.Movies.Movie'
-- @param @IsPlayed 0
-- @param @Genre0 'action'
-- @param @Genre1 'science fiction'
-- @param @OfficialRating0 'PG-13'
-- @param @OfficialRating1 'R'
-- @param @TopParentId '9e377a1200014e379eef000000000001'
select count (distinct
  PresentationUniqueKey),UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND (played is null or played=@IsPlayed)
  AND (@Genre0 in (select CleanValue from ItemValues where ItemId=Guid and Type=2) OR @Genre1 in (select CleanValue from ItemValues where ItemId=Guid and Type=2))
  AND (OfficialRating=@OfficialRating0 OR OfficialRating=@OfficialRating1)
  AND ProductionYear in (1980,1981,1982,1983,1984,1985,1986,1987,1988,1989,1990,1991,1992,1993,1994,1995,1996,1997,1998,1999)
  AND (TopParentId=@TopParentId);

-- @id jellyfin.browse.series_unplayed
-- @src Jellyfin.Api/Controllers/ItemsController.cs:160-521 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (IsPlayed for Series 3523-3533)
-- @style @name params; dynamic WHERE
-- @tags hotpath,dynamic
-- @note TV Shows grid with Unplayed filter: PresentationUniqueKey IN (episodes LEFT JOIN UserDatas WHERE Coalesce(Played,0)=0) subquery over all episodes.
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.TV.Series'
-- @param @TopParentId '3c6ef3c300014c6ebdde000000000002'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND PresentationUniqueKey in (select S.SeriesPresentationUniqueKey from TypedBaseitems S left join UserDatas UD on S.UserDataKey=UD.Key And UD.UserId=@UserId where Coalesce(UD.Played, 0)=0 and S.IsFolder=0 and S.IsVirtualItem=0 and S.SeriesPresentationUniqueKey not null)
  AND (TopParentId=@TopParentId)
Group by PresentationUniqueKey
ORDER BY SortName ASC
LIMIT 100;

-- @id jellyfin.browse.series_by_date_played
-- @src Jellyfin.Api/Controllers/ItemsController.cs:160-521 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (SeriesDatePlayed 2864)
-- @style @name params; ORDER BY term is a correlated MAX() subquery with its own UserDatas join
-- @tags hotpath,dynamic
-- @note TV Shows sorted by 'Date played': per-series correlated MAX(LastPlayedDate) over its episodes joined to UserDatas, evaluated as a sort key.
-- @param @UserId 1
-- @param @type 'MediaBrowser.Controller.Entities.TV.Series'
-- @param @TopParentId '3c6ef3c300014c6ebdde000000000002'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type=@type
  AND (TopParentId=@TopParentId)
Group by PresentationUniqueKey
ORDER BY (Select MAX(LastPlayedDate) from TypedBaseItems B left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId) where Played=1 and B.SeriesPresentationUniqueKey=A.PresentationUniqueKey) DESC,SortName ASC
LIMIT 100;

-- @id jellyfin.browse.albums_by_album_artist
-- @src Jellyfin.Api/Controllers/ItemsController.cs:160-521 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (AlbumArtist sort 2861)
-- @style @name params; ORDER BY term is a correlated LIMIT 1 subquery
-- @tags hotpath,dynamic
-- @note Music albums grid sorted by Album Artist: correlated ItemValues lookup as a sort key, no GROUP BY (MusicAlbum is not grouped).
-- @param @type 'MediaBrowser.Controller.Entities.Audio.MusicAlbum'
-- @param @TopParentId 'daa66d7400014aa59ccd000000000003'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,OwnerId from TypedBaseItems A
where type=@type
  AND (TopParentId=@TopParentId)
ORDER BY (select CleanValue from ItemValues where ItemId=Guid and Type=1 LIMIT 1) ASC,SortName ASC
LIMIT 100;

-- @id jellyfin.artist.albums
-- @src Jellyfin.Api/Controllers/ItemsController.cs:355-521 -> LibraryManager.cs:1522 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (ArtistIds 3569)
-- @style @name params; ArtistIds expand to nested IN/scalar subqueries
-- @tags hotpath,dynamic
-- @note Artist page album list: guid IN (ItemValues WHERE CleanValue = (scalar CleanName of the artist) AND Type<=1).
-- @param @type 'MediaBrowser.Controller.Entities.Audio.MusicAlbum'
-- @param @ArtistIds0 x'9e377bf700064e379eef000000000001'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,OwnerId from TypedBaseItems A
where type=@type
  AND ((guid in (select itemid from ItemValues where CleanValue = (select CleanName from TypedBaseItems where guid=@ArtistIds0) and Type<=1)))
  AND TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004')
ORDER BY ProductionYear DESC,SortName ASC
LIMIT 100;

-- @id jellyfin.browse.favorites
-- @src Jellyfin.Api/Controllers/ItemsController.cs:318-521 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534
-- @style @name params; multiple IncludeItemTypes become a literal IN list
-- @tags hotpath,dynamic
-- @note Favorites page: UserDatas join with IsFavorite=1 across movies and series of all libraries.
-- @param @UserId 1
-- @param @IsFavorite 1
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,UserDatas.UserId,UserDatas.lastPlayedDate,UserDatas.playbackPositionTicks,UserDatas.playcount,UserDatas.isFavorite,UserDatas.played,UserDatas.rating from TypedBaseItems A left join UserDatas on UserDataKey=UserDatas.Key And (UserId=@UserId)
where type in ('MediaBrowser.Controller.Entities.Movies.Movie','MediaBrowser.Controller.Entities.TV.Series')
  AND IsFavorite=@IsFavorite
  AND TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004')
Group by PresentationUniqueKey
ORDER BY SortName ASC
LIMIT 20;

-- @id jellyfin.search.hints
-- @src Emby.Server.Implementations/Library/SearchEngine.cs:144-195 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (SearchScore 2331-2347, IncludeItemsByName 4133)
-- @style @name params; SearchScore column computed from LIKE/COLLATE NOCASE tests and filtered by alias in WHERE
-- @tags hotpath,dynamic
-- @note Search hints: computed SearchScore (3 LIKE / NOCASE terms) used in WHERE and ORDER BY, items-by-name types OR'ed with TopParentId IN list.
-- @param @SearchTermStartsWith 'star%'
-- @param @SearchTermContains '%star%'
select type,data,StartDate,EndDate,ChannelId,IsMovie,IsSeries,EpisodeTitle,IsRepeat,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateCreated,DateModified,guid,ParentId,Audio,ExternalServiceId,IsInMixedFolder,Tags,TrailerTypes,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,ShowId,OwnerId,(((CleanName
  like @SearchTermStartsWith or (OriginalTitle not null and OriginalTitle like @SearchTermStartsWith)) * 10)+
  ((CleanName = @SearchTermStartsWith COLLATE NOCASE or (OriginalTitle not null and OriginalTitle =
  @SearchTermStartsWith COLLATE NOCASE)) * 10)+ ((CleanName like @SearchTermContains or (OriginalTitle not null and
  OriginalTitle like @SearchTermContains)) * 10)) as SearchScore from TypedBaseItems A
where SearchScore > 0
  AND type not in ('MediaBrowser.Controller.Entities.Year','MediaBrowser.Controller.Entities.Folder','MediaBrowser.Controller.Entities.CollectionFolder')
  AND (Type in ('MediaBrowser.Controller.Entities.Person','MediaBrowser.Controller.Entities.Genre','MediaBrowser.Controller.Entities.Audio.MusicGenre','MediaBrowser.Controller.Entities.Audio.MusicArtist','MediaBrowser.Controller.Entities.Studio') or TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004'))
Group by PresentationUniqueKey
ORDER BY SearchScore DESC,SortName ASC,SortName ASC
LIMIT 20;

-- @id jellyfin.similar.movies
-- @src Jellyfin.Api/Controllers/LibraryController.cs:778-796 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:2486-2534 (SimilarityScore 2275-2329)
-- @style @name params; SimilarityScore column of CASE and correlated count subqueries, filtered by alias
-- @tags hotpath,dynamic
-- @note 'More like this' on a movie page: per-candidate correlated counts of shared ItemValues and People, CASE year/rating terms, genre pre-filter, top 12+4.
-- @modified ORDER BY's second key RANDOM() (ItemSortBy.Random, prepended by GetOrderByText) replaced by guid so results are deterministic
-- @param @InheritedParentalRatingValue 9
-- @param @ItemProductionYear 1988
-- @param @SimilarItemId x'3db842ad00024d8dbef500000000005b'
-- @param @type 'MediaBrowser.Controller.Entities.Movies.Movie'
-- @param @Genre0 'sci-fi & fantasy'
-- @param @Genre1 'mystery'
-- @param @ExcludeId0 x'3db842ad00024d8dbef500000000005b'
-- @param @ExcludeProviderId0 '%Tmdb=100091%'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,((SELECT
  CASE WHEN COALESCE(InheritedParentalRatingValue, 0)=0 THEN 0 ELSE 10.0 / (1.0 + ABS(InheritedParentalRatingValue -
  @InheritedParentalRatingValue)) END)+(Select Case When Abs(COALESCE(ProductionYear, 0) - @ItemProductionYear) < 10
  Then 10 Else 0 End )+(Select Case When Abs(COALESCE(ProductionYear, 0) - @ItemProductionYear) < 5 Then 5 Else 0 End
  )+ (Select count(1) * 10 from ItemValues where ItemId=Guid and CleanValue in (select CleanValue from ItemValues
  where ItemId=@SimilarItemId))+ (Select count(1) * 10 from People where ItemId=Guid and Name in (select Name from
  People where ItemId=@SimilarItemId))) as SimilarityScore from TypedBaseItems A
where SimilarityScore > 1
  AND type=@type
  AND (@Genre0 in (select CleanValue from ItemValues where ItemId=Guid and Type=2) OR @Genre1 in (select CleanValue from ItemValues where ItemId=Guid and Type=2))
  AND Guid <> @ExcludeId0
  AND (ProviderIds is null or ProviderIds not like @ExcludeProviderId0)
  AND TopParentId in ('9e377a1200014e379eef000000000001','3c6ef3c300014c6ebdde000000000002','daa66d7400014aa59ccd000000000003','78dde725000148dcbbbc000000000004')
Group by PresentationUniqueKey
ORDER BY SimilarityScore DESC,guid ASC
LIMIT 16;

-- @id jellyfin.genres.movies_with_counts
-- @src Jellyfin.Api/Controllers/GenresController.cs:105-142 -> LibraryManager.cs:1382 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:4831-4990
-- @style @name params; GetItemValues: item-type count column, IN (ItemValues IN (TypedBaseItems)) chain
-- @tags hotpath,dynamic
-- @note Genres tab of the Movies library: Genre items whose CleanName is used by a movie in the library, with a correlated group_concat of matching item types per genre.
-- @param @type 'MediaBrowser.Controller.Entities.Movies.Movie'
-- @param @TopParentId '9e377a1200014e379eef000000000001'
-- @param @SelectType 'MediaBrowser.Controller.Entities.Genre'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,ExternalId,OwnerId,(select
  group_concat(type, '|') from TypedBaseItems B where type=@type AND (TopParentId=@TopParentId) AND guid in (select
  ItemId from ItemValues where ItemValues.CleanValue=A.CleanName AND Type=2)) as itemTypes from TypedBaseItems A where Type=@SelectType And CleanName In (Select CleanValue from ItemValues where Type=2 AND ItemId in (select guid from TypedBaseItems where type=@type AND (TopParentId=@TopParentId))) group by PresentationUniqueKey ORDER BY SortName ASC;

-- @id jellyfin.genres.music_with_counts
-- @src Jellyfin.Api/Controllers/GenresController.cs:105-138 -> LibraryManager.cs:1393 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:4831-4990
-- @style @name params; GetItemValues with two counted item types and an outer NameStartsWith filter
-- @tags hotpath,dynamic
-- @note Music genres page: MusicGenre items used by albums/tracks in the music library, group_concat of item types per genre (later split into counts), paged.
-- @param @TopParentId 'daa66d7400014aa59ccd000000000003'
-- @param @SelectType 'MediaBrowser.Controller.Entities.Audio.MusicGenre'
-- @param @NameStartsWith 'r%'
select type,data,EndDate,ChannelId,CommunityRating,IndexNumber,Width,Height,Name,Path,PremiereDate,ParentIndexNumber,ProductionYear,OfficialRating,RunTimeTicks,Size,DateModified,guid,ParentId,Audio,IsInMixedFolder,PrimaryVersionId,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,ProviderIds,Images,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,OwnerId,(select
  group_concat(type, '|') from TypedBaseItems B where type in
  ('MediaBrowser.Controller.Entities.Audio.MusicAlbum','MediaBrowser.Controller.Entities.Audio.Audio') AND
  (TopParentId=@TopParentId) AND guid in (select ItemId from ItemValues where ItemValues.CleanValue=A.CleanName AND
  Type=2)) as itemTypes from TypedBaseItems A where Type=@SelectType And CleanName In (Select CleanValue from ItemValues where Type=2 AND ItemId in (select guid from TypedBaseItems where type in ('MediaBrowser.Controller.Entities.Audio.MusicAlbum','MediaBrowser.Controller.Entities.Audio.Audio') AND (TopParentId=@TopParentId))) AND SortName like @NameStartsWith group by PresentationUniqueKey ORDER BY SortName ASC LIMIT 50;

-- @id jellyfin.genres.music_total_count
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:4999-5011
-- @style @name params; same whereText as the page query
-- @tags hotpath,dynamic
-- @note Total count for the music genres page: count(distinct PresentationUniqueKey) over the IN-chain.
-- @param @TopParentId 'daa66d7400014aa59ccd000000000003'
-- @param @SelectType 'MediaBrowser.Controller.Entities.Audio.MusicGenre'
-- @param @NameStartsWith 'r%'
select count (distinct PresentationUniqueKey) from TypedBaseItems A where Type=@SelectType And CleanName In (Select CleanValue from ItemValues where Type=2 AND ItemId in (select guid from TypedBaseItems where type in ('MediaBrowser.Controller.Entities.Audio.MusicAlbum','MediaBrowser.Controller.Entities.Audio.Audio') AND (TopParentId=@TopParentId))) AND SortName like @NameStartsWith;

-- @id jellyfin.genres.names_for_types
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:4766-4830
-- @style string-built literal type lists, no params
-- @tags dynamic
-- @note Genre name list for the filter dialog: ItemValues grouped by CleanValue with IN / NOT IN item-type subqueries.
Select Value From ItemValues where Type=2 AND ItemId In (select guid from typedbaseitems where type in ('MediaBrowser.Controller.Entities.Movies.Movie','MediaBrowser.Controller.Entities.TV.Series')) AND ItemId not In (select guid from typedbaseitems where type in ('MediaBrowser.Controller.Entities.Audio.MusicAlbum','MediaBrowser.Controller.Entities.Audio.Audio')) Group By CleanValue;

-- @id jellyfin.people.favorite_actors
-- @src Jellyfin.Api/Controllers/PersonsController.cs:92-100 -> Emby.Server.Implementations/Data/SqliteItemRepository.cs:4504-4541 (where 4581-4650)
-- @style @name params; dynamic WHERE
-- @tags hotpath,dynamic
-- @note People page with Favorites filter: DISTINCT names through a 3-level IN chain People -> TypedBaseItems.UserDataKey -> UserDatas.
-- @param @IsFavorite 1
-- @param @UserId 1
-- @param @InternalPersonType 'MediaBrowser.Controller.Entities.Person'
-- @param @PersonType 'Actor'
select Distinct p.Name from People p where p.Name IN (
SELECT Name FROM TypedBaseItems WHERE UserDataKey IN (
SELECT key FROM UserDatas WHERE isFavorite=@IsFavorite AND userId=@UserId)
AND Type = @InternalPersonType) AND PersonType=@PersonType order by ListOrder LIMIT 100;

-- @id jellyfin.people.for_item
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:4543-4580
-- @style @name params
-- @tags hot-small,hotpath
-- @note Cast & crew for an item page: People range scan on idxPeopleItemId1.
-- @param @ItemId x'3db842ad00024d8dbef500000000005b'
select ItemId, Name, Role, PersonType, SortOrder from People p  where ItemId=@ItemId order by ListOrder;

-- @id jellyfin.item.retrieve_by_guid
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:137,1257-1278
-- @style @name param
-- @tags hot-small,hotpath
-- @note RetrieveItem: the full 69-column row by guid, called for every GetItemById cache miss.
-- @param @guid x'11a25cbc00024196a44600000000001a'
select type,data,StartDate,EndDate,ChannelId,IsMovie,IsSeries,EpisodeTitle,IsRepeat,CommunityRating,CustomRating,IndexNumber,IsLocked,PreferredMetadataLanguage,PreferredMetadataCountryCode,Width,Height,DateLastRefreshed,Name,Path,PremiereDate,Overview,ParentIndexNumber,ProductionYear,OfficialRating,ForcedSortName,RunTimeTicks,Size,DateCreated,DateModified,guid,Genres,ParentId,Audio,ExternalServiceId,IsInMixedFolder,DateLastSaved,LockedFields,Studios,Tags,TrailerTypes,OriginalTitle,PrimaryVersionId,DateLastMediaAdded,Album,LUFS,NormalizationGain,CriticRating,IsVirtualItem,SeriesName,SeasonName,SeasonId,SeriesId,PresentationUniqueKey,InheritedParentalRatingValue,ExternalSeriesId,Tagline,ProviderIds,Images,ProductionLocations,ExtraIds,TotalBitrate,ExtraType,Artists,AlbumArtists,ExternalId,SeriesPresentationUniqueKey,ShowId,OwnerId from TypedBaseItems where guid = @guid;

-- @id jellyfin.userdata.get
-- @src Emby.Server.Implementations/Data/SqliteUserDataRepository.cs:272-276
-- @style @name params
-- @tags hot-small,hotpath
-- @note Per-item user data lookup (played/position/favourite) on the unique (key, userId) index, once per DTO.
-- @param @Key '100026'
-- @param @UserId 1
select key,userid,rating,played,playCount,isFavorite,playbackPositionTicks,lastPlayedDate,AudioStreamIndex,SubtitleStreamIndex from UserDatas where key =@Key and userId=@UserId;

-- @id jellyfin.userdata.save
-- @src Emby.Server.Implementations/Data/SqliteUserDataRepository.cs:181-226
-- @style @name params
-- @tags hot-small,hotpath
-- @note Playback progress report: REPLACE INTO UserDatas, sent every few seconds while a client plays.
-- @param @key '100026'
-- @param @userId 1
-- @param @rating NULL
-- @param @played 0
-- @param @playCount 0
-- @param @isFavorite 0
-- @param @playbackPositionTicks 31230000000
-- @param @lastPlayedDate '2026-10-27 21:14:03.1234567Z'
-- @param @AudioStreamIndex 1
-- @param @SubtitleStreamIndex -1
replace into UserDatas (key, userId, rating,played,playCount,isFavorite,playbackPositionTicks,lastPlayedDate,AudioStreamIndex,SubtitleStreamIndex) values (@key, @userId, @rating,@played,@playCount,@isFavorite,@playbackPositionTicks,@lastPlayedDate,@AudioStreamIndex,@SubtitleStreamIndex);

-- @id jellyfin.mediastreams.for_item
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:139-192,5346-5393
-- @style @name params; optional StreamType/StreamIndex appended
-- @tags hot-small,hotpath
-- @note Media streams of an item for playback info / DTO MediaSources: PK range on (ItemId, StreamIndex).
-- @param @ItemId x'3db842ad00024d8dbef500000000005b'
select ItemId,StreamIndex,StreamType,Codec,Language,ChannelLayout,Profile,AspectRatio,Path,IsInterlaced,BitRate,Channels,SampleRate,IsDefault,IsForced,IsExternal,Height,Width,AverageFrameRate,RealFrameRate,Level,PixelFormat,BitDepth,IsAnamorphic,RefFrames,CodecTag,Comment,NalLengthSize,IsAvc,Title,TimeBase,CodecTimeBase,ColorPrimaries,ColorSpace,ColorTransfer,DvVersionMajor,DvVersionMinor,DvProfile,DvLevel,RpuPresentFlag,ElPresentFlag,BlPresentFlag,DvBlSignalCompatibilityId,IsHearingImpaired,Rotation from mediastreams where ItemId=@ItemId order by StreamIndex ASC;

-- @id jellyfin.chapters.for_item
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:1887-1905
-- @style @name params
-- @tags hot-small,hotpath
-- @note Chapter list for an item: PK range on Chapters2 (ItemId, ChapterIndex).
-- @param @ItemId x'3db842ad00024d8dbef500000000005b'
select StartPositionTicks,Name,ImagePath,ImageDateModified from Chapters2 where ItemId = @ItemId order by ChapterIndex asc;

-- @id jellyfin.library.inherit_tags_from_ancestors
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:4444-4459
-- @style fixed SQL, third statement of the UpdateInheritedValues batch
-- @tags batch
-- @note Post-scan rebuild of inherited tags: INSERT ... SELECT over AncestorIds LEFT JOIN ItemValues (the LEFT JOIN is turned inner by the WHERE).
insert into ItemValues (ItemId, Type, Value, CleanValue) select AncestorIds.itemid, 6, ItemValues.Value, ItemValues.CleanValue
FROM AncestorIds
LEFT JOIN ItemValues ON (AncestorIds.AncestorId = ItemValues.ItemId)
where AncestorIdText not null and ItemValues.Value not null and ItemValues.Type = 4;

-- @id jellyfin.library.insert_item_values
-- @src Emby.Server.Implementations/Data/SqliteItemRepository.cs:5196-5242
-- @style @name params; multi-row VALUES built per item (one row per genre/studio/tag/artist)
-- @tags batch,dynamic
-- @note Saving an item during a scan: multi-row INSERT of its ItemValues after the delete.
-- @param @ItemId x'11a25cbc00024196a44600000000001a'
-- @param @Type0 2
-- @param @Value0 'Drama'
-- @param @CleanValue0 'drama'
-- @param @Type1 2
-- @param @Value1 'Thriller'
-- @param @CleanValue1 'thriller'
-- @param @Type2 3
-- @param @Value2 'Studio 7'
-- @param @CleanValue2 'studio 7'
-- @param @Type3 4
-- @param @Value3 'Christmas'
-- @param @CleanValue3 'christmas'
insert into ItemValues (ItemId, Type, Value, CleanValue) values (@ItemId, @Type0, @Value0, @CleanValue0),(@ItemId, @Type1, @Value1, @CleanValue1),(@ItemId, @Type2, @Value2, @CleanValue2),(@ItemId, @Type3, @Value3, @CleanValue3);
