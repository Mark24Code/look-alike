import axios from 'axios';
import type { Project, FileNode, FileData } from '../types';

const api = axios.create({
    baseURL: '/api'
});

export const getProjects = async (page = 1) => {
    const res = await api.get<{ projects: Project[], total: number }>(`/projects?page=${page}`);
    return res.data;
};

export const createProject = async (data: { name: string, source_path: string, targets: { name: string, path: string }[] }) => {
    const res = await api.post('/projects', data);
    return res.data;
};

export const deleteProject = async (id: number) => {
    await api.delete(`/projects/${id}`);
};

export const getProject = async (id: number) => {
    const res = await api.get<Project>(`/projects/${id}`);
    return res.data;
};

export const getProjectFiles = async (id: number) => {
    const res = await api.get<FileNode>(`/projects/${id}/files`);
    return res.data;
};

export const getCandidates = async (id: number, file_ids: number[]) => {
    const res = await api.post<Record<string, FileData>>(`/projects/${id}/candidates`, { file_ids });
    return res.data;
};

// Select a candidate for a specific target
export const selectCandidate = async (projectId: number, sourceFileId: number, projectTargetId: number, selectedCandidateId: number) => {
    await api.post(`/projects/${projectId}/select_candidate`, {
        source_file_id: sourceFileId,
        project_target_id: projectTargetId,
        selected_candidate_id: selectedCandidateId
    });
};

// Mark a target as having no match
export const markNoMatch = async (projectId: number, sourceFileId: number, projectTargetId: number) => {
    await api.post(`/projects/${projectId}/mark_no_match`, {
        source_file_id: sourceFileId,
        project_target_id: projectTargetId
    });
};

// Confirm/unconfirm entire row
export const confirmRow = async (projectId: number, sourceFileId: number, confirmed: boolean) => {
    await api.post(`/projects/${projectId}/confirm_row`, {
        source_file_id: sourceFileId,
        confirmed
    });
};

export const exportProject = async (id: number, usePlaceholder: boolean = true, onlyConfirmed: boolean = false, outputPath?: string) => {
    await api.post(`/projects/${id}/export`, {
        use_placeholder: usePlaceholder,
        only_confirmed: onlyConfirmed,
        output_path: outputPath
    });
};

export const getExportProgress = async (id: number) => {
    const res = await api.get<{ total: number, processed: number, current: string, status: string }>(`/projects/${id}/export_progress`);
    return res.data;
};
