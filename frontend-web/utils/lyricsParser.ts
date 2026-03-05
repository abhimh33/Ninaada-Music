export interface LyricsLine {
  text: string;
  startTime: number;
  endTime: number;
}

export function parseLyrics(lyrics: string, duration: number): LyricsLine[] {
  if (!lyrics || !duration || duration <= 0) return [];
  
  // Clean HTML tags and convert <br> to newlines
  let cleanLyrics = lyrics
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/?[^>]+(>|$)/g, '') // Remove all HTML tags
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'");
  
  // Split lyrics into lines and filter empty lines
  const lines = cleanLyrics.split('\n').filter(line => line.trim().length > 0);
  if (lines.length === 0) return [];
  
  const totalLines = lines.length;
  
  // Calculate time per line (simple distribution)
  const timePerLine = duration / totalLines;
  
  return lines.map((line, index) => ({
    text: line.trim(),
    startTime: index * timePerLine,
    endTime: (index + 1) * timePerLine,
  }));
}

export function getCurrentLyricsLine(lyricsLines: LyricsLine[], currentTime: number): number {
  if (!lyricsLines || lyricsLines.length === 0 || !isFinite(currentTime) || currentTime < 0) {
    return -1;
  }
  
  // Find the line that matches the current time
  for (let i = 0; i < lyricsLines.length; i++) {
    const line = lyricsLines[i];
    if (currentTime >= line.startTime && currentTime < line.endTime) {
      return i;
    }
  }
  
  // If past the last line, return the last line index
  if (currentTime >= lyricsLines[lyricsLines.length - 1].endTime) {
    return lyricsLines.length - 1;
  }
  
  return -1;
}

