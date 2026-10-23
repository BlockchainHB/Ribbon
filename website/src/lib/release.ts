import release from '../../../release.json';

function publicLink(value: string | undefined): string | undefined {
  const url = value?.trim();
  if (!url) return undefined;
  if (new URL(url).protocol !== 'https:') throw new Error('Public links must use HTTPS.');
  return url;
}

const repository = 'https://github.com/BlockchainHB/Ribbon';

export const releaseTag = release.tag;

export const links = {
  download: publicLink(import.meta.env.PUBLIC_DOWNLOAD_URL) ?? `${repository}/releases/download/${release.tag}/${release.asset}`,
  repository: publicLink(import.meta.env.PUBLIC_REPOSITORY_URL) ?? repository,
  releases: publicLink(import.meta.env.PUBLIC_RELEASES_URL) ?? `${repository}/releases`,
};
