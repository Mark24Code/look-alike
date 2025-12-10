import { atom } from 'jotai';
import type { Project } from '../types';

export const projectsAtom = atom<Project[]>([]);
export const currentProjectAtom = atom<Project | null>(null);
