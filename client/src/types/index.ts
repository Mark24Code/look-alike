export interface Project {
    id: number;
    name: string;
    source_path: string;
    status: 'pending' | 'indexing' | 'indexed' | 'comparing' | 'processing' | 'scanned' | 'completed' | 'error';
    error_message?: string;
    created_at: string;
    started_at?: string;
    ended_at?: string;
    output_path?: string;
    stats?: {
        total_files: number;
        processed: number;
        progress: number;
    };
    targets?: ProjectTarget[];
    confirmation_stats?: {
        confirmed: number;
        total: number;
    };
    duplicate_warnings?: Array<{
        relative_path: string;
        count: number;
        files: string[];
    }>;
}

export interface ProjectTarget {
    id: number;
    name: string;
    path: string;
}

export interface FileNode {
    name: string;
    key: string;
    isLeaf?: boolean;
    children?: FileNode[];
    file_id?: number;
    status?: string;
    confirmed?: boolean;
}

export interface FileData {
    source: {
        path: string;
        relative: string;
        thumb_url: string;
        width?: number;
        height?: number;
        size_bytes?: number;
    };
    candidates: Record<string, Array<{
        id: number;
        path: string;
        similarity: number;
        width?: number;
        height?: number;
    }>>;
    target_selections: Record<string, {
        selected_candidate_id?: number;
        no_match: boolean;
    }>;
    confirmed: boolean;
    source_file_id?: number;
}
