export interface DirEntry {
  name: string;
  is_dir: boolean;
  ext: string;
  thumbnail?: string;
}

export interface PageState {
  name: string;
  orig_name: string;
  gone: boolean;
  orig_index: number;
  data?: string | null;
}

export interface ArchiveEntry {
  name: string;
  size: number;
}

export interface FirstImageResult {
  name: string | null;
  thumbnail: string | null;
}

export interface ImageCheck {
  filename: string;
  ok: boolean;
  errors: string[];
}

export interface FileValidationResult {
  file_name: string;
  valid: boolean;
  image_count: number;
  error_msg: string | null;
  image_checks: ImageCheck[];
}

export interface ProgressEvent {
  percent: number;
  message: string;
  phase: string;
}

export interface SaveChangesResult {
  success: boolean;
  error_msg: string | null;
}

export interface ComicInfoResult {
  file_name: string;
  found: boolean;
  message?: string;
}

export interface CbrConversionResult {
  input: string;
  output: string | null;
  ok: boolean;
  error: string | null;
}

export interface MergeVolume {
  title: string;
  output_path: string;
  chapters: string[];
}

export interface MergeResult {
  volumes_created: MergeVolume[];
  total_pages: number;
  error_msg: string | null;
}

export interface ConvertWebpResult {
  dir_path: string;
  converted: string[];
  skipped: string[];
}

export interface ColorAdjustParams {
  grayscale: boolean;
  sepia: boolean;
  invert: boolean;
  red_gain: number;
  green_gain: number;
  blue_gain: number;
  saturation: number;
  contrast: number;
  brightness: number;
  gamma: number;
}

export interface BatchEditParams {
  resize_percent: number;
  color_adjust: ColorAdjustParams;
  /** Uniform split lines (normalised 0-1), applied to every page. */
  cut_lines: number[];
  /** True = horizontal cut lines (top/bottom), false = vertical. */
  horizontal_lines: boolean;
}
