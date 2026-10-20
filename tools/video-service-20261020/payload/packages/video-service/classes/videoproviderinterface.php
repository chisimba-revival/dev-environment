<?php
/** Provider-neutral hosted-video boundary. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
interface VideoProviderInterface
{
    public function configured(): bool;
    public function capabilities(): array;
    public function createUpload(string $videoId, string $origin): array;
    public function processingStatus(array $video): array;
    public function metadata(string $assetId): array;
    public function authorisePlayback(string $playbackId, int $expires): array;
    public function deleteHostedVideo(array $video): void;
}
