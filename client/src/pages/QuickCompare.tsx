import React, { useEffect, useState, useMemo, useRef } from 'react';
import { Table, Button, Input, Space, Image, message, Checkbox, InputNumber, Select, Modal, List, Radio, Progress } from 'antd';
import { useParams } from 'react-router-dom';
import { getProjectFiles, getCandidates, selectCandidate, markNoMatch, confirmRow, exportProject, getProject, getExportProgress } from '../api';
import type { FileNode, FileData, ProjectTarget } from '../types';
import { ExportOutlined, CheckSquareOutlined, StopOutlined, CheckCircleFilled } from '@ant-design/icons';

const { Option } = Select;

type TableItem = FileData & { source_file_id: number };

const QuickCompare: React.FC = () => {
    const { id } = useParams<{ id: string }>();
    const projectId = Number(id);

    // Data State
    const [tableData, setTableData] = useState<TableItem[]>([]);
    const [filteredData, setFilteredData] = useState<TableItem[]>([]);
    const [loading, setLoading] = useState(false);
    const [projectTargets, setProjectTargets] = useState<ProjectTarget[]>([]);
    const [projectOutputPath, setProjectOutputPath] = useState<string>('');
    const [projectName, setProjectName] = useState<string>('');
    const [projectSourcePath, setProjectSourcePath] = useState<string>('');

    // Export Progress State
    const [exportProgress, setExportProgress] = useState<{ total: number, processed: number, current: string } | null>(null);
    const [isExporting, setIsExporting] = useState(false);
    const exportPathRef = useRef<string>(''); // 使用 ref 存储导出路径，避免闭包问题

    // Filters
    const [searchText, setSearchText] = useState('');
    const [minWidth, setMinWidth] = useState<number | null>(null);
    const [minHeight, setMinHeight] = useState<number | null>(null);
    const [confirmFilter, setConfirmFilter] = useState<'all' | 'confirmed' | 'unconfirmed'>('all');
    const [orientationFilter, setOrientationFilter] = useState<'all' | 'square' | 'landscape' | 'portrait'>('all');

    // Selection
    const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([]);

    // Pagination State
    const [currentPage, setCurrentPage] = useState(1);
    const [pageSize, setPageSize] = useState(20);

    // Modal State - for selecting candidates
    const [modalVisible, setModalVisible] = useState(false);
    const [currentCandidates, setCurrentCandidates] = useState<any[]>([]);
    const [currentSourceId, setCurrentSourceId] = useState<number | null>(null);
    const [currentTargetId, setCurrentTargetId] = useState<number | null>(null);
    const [currentTargetName, setCurrentTargetName] = useState<string>('');
    const [currentSourceImage, setCurrentSourceImage] = useState<{ path: string, width: number, height: number } | null>(null);
    const [selectedCandidateInModal, setSelectedCandidateInModal] = useState<number | null>(null);

    // Helper to collect file IDs from tree
    const collectFileIds = (node: FileNode): number[] => {
        let ids: number[] = [];
        if (node.file_id) ids.push(node.file_id);
        if (node.children) {
            node.children.forEach(child => {
                ids = ids.concat(collectFileIds(child));
            });
        }
        return ids;
    };

    // Fetch data
    useEffect(() => {
        if (!projectId) return;

        setLoading(true);
        Promise.all([
            getProject(projectId),
            getProjectFiles(projectId)
        ]).then(([project, root]) => {
            setProjectTargets(project.targets || []);
            setProjectOutputPath(project.output_path || '');
            setProjectName(project.name || '');
            setProjectSourcePath(project.source_path || '');

            // Check for duplicate warnings
            if (project.duplicate_warnings && project.duplicate_warnings.length > 0) {
                Modal.warning({
                    title: '检测到重复的图片文件名',
                    width: 700,
                    content: (
                        <div>
                            <p style={{ marginBottom: 12 }}>以下文件名在源目录中出现了重复，可能会导致导出时文件覆盖：</p>
                            <div style={{ maxHeight: 400, overflow: 'auto' }}>
                                {project.duplicate_warnings.map((dup, index) => (
                                    <div key={index} style={{ marginBottom: 16, padding: 12, background: '#f5f5f5', borderRadius: 4 }}>
                                        <div style={{ fontWeight: 'bold', marginBottom: 8 }}>
                                            文件名: {dup.relative_path} (出现 {dup.count} 次)
                                        </div>
                                        <div style={{ fontSize: 12, color: '#666' }}>
                                            {dup.files.map((file, i) => (
                                                <div key={i} style={{ marginBottom: 4 }}>
                                                    {i + 1}. {file}
                                                </div>
                                            ))}
                                        </div>
                                    </div>
                                ))}
                            </div>
                            <p style={{ marginTop: 12, color: '#ff4d4f' }}>
                                建议：检查并重命名重复的文件，确保每个文件名唯一。
                            </p>
                        </div>
                    )
                });
            }

            const ids = collectFileIds(root);
            return getCandidates(projectId, ids);
        }).then(data => {
            const list: TableItem[] = [];
            Object.keys(data).forEach(key => {
                const fid = Number(key);
                if (data[key]) {
                    list.push({ ...data[key], source_file_id: fid });
                }
            });
            list.sort((a, b) => a.source.relative.localeCompare(b.source.relative));
            setTableData(list);
        }).catch(err => {
            console.error(err);
            message.error('加载对比数据失败');
        }).finally(() => {
            setLoading(false);
        });
    }, [projectId]);

    // Filter effect
    useEffect(() => {
        let res = tableData;
        if (searchText) {
            const lower = searchText.toLowerCase();
            res = res.filter(item => item.source.relative.toLowerCase().includes(lower));
        }
        if (minWidth !== null) res = res.filter(item => (item.source.width || 0) >= minWidth);
        if (minHeight !== null) res = res.filter(item => (item.source.height || 0) >= minHeight);
        if (confirmFilter === 'confirmed') res = res.filter(item => item.confirmed);
        else if (confirmFilter === 'unconfirmed') res = res.filter(item => !item.confirmed);

        // Orientation filter
        if (orientationFilter !== 'all') {
            res = res.filter(item => {
                const width = item.source.width || 0;
                const height = item.source.height || 0;
                const ratio = width / height;

                if (orientationFilter === 'square') {
                    return ratio >= 0.9 && ratio <= 1.1;
                } else if (orientationFilter === 'landscape') {
                    return ratio > 1.1;
                } else if (orientationFilter === 'portrait') {
                    return ratio < 0.9;
                }
                return true;
            });
        }

        setFilteredData(res);
        // Reset to first page when filters change
        setCurrentPage(1);
    }, [searchText, minWidth, minHeight, confirmFilter, orientationFilter, tableData]);

    // Toggle confirmation status
    const handleConfirm = async (record: TableItem, confirmed: boolean) => {
        try {
            await confirmRow(projectId, record.source_file_id, confirmed);
            setTableData(prev => prev.map(item => {
                if (item.source_file_id === record.source_file_id) {
                    return { ...item, confirmed };
                }
                return item;
            }));
        } catch (e) {
            message.error('更新确认状态失败');
        }
    };

    // Batch confirm
    const handleBatchConfirm = async (confirmed: boolean) => {
        if (selectedRowKeys.length === 0) {
            message.warning('未选择任何项目');
            return;
        }
        setLoading(true);
        try {
            for (const key of selectedRowKeys) {
                const id = Number(key);
                await confirmRow(projectId, id, confirmed);
            }
            setTableData(prev => prev.map(item => {
                if (selectedRowKeys.includes(item.source_file_id)) {
                    return { ...item, confirmed };
                }
                return item;
            }));
            setSelectedRowKeys([]);
            message.success('批量更新' + (confirmed ? '已确认' : '已取消确认'));
        } catch (e) {
            message.error('批量更新失败');
        } finally {
            setLoading(false);
        }
    };

    // Export handler
    const handleExport = async () => {
        let usePlaceholder = true;
        let onlyConfirmed = false;

        // 计算默认导出路径：源图片目录/项目名_exports
        const getDefaultExportPath = () => {
            if (!projectSourcePath || !projectName) return projectOutputPath;

            // 获取源路径的父目录
            const pathParts = projectSourcePath.split('/');
            pathParts.pop(); // 移除最后一个部分（源图片目录名）
            const parentDir = pathParts.join('/') || '/';

            // 返回: 父目录/项目名_exports
            return `${parentDir}/${projectName}_exports`;
        };

        const defaultExportPath = getDefaultExportPath();
        let exportPath = defaultExportPath;

        Modal.confirm({
            title: '确认导出',
            width: 600,
            content: (
                <div>
                    <p style={{ marginBottom: 16 }}>确定要导出图片匹配结果吗？</p>

                    <div style={{ marginBottom: 12 }}>
                        <div style={{ marginBottom: 4, fontSize: 13, fontWeight: 500 }}>导出路径：</div>
                        <Input
                            defaultValue={defaultExportPath}
                            onChange={(e) => { exportPath = e.target.value; }}
                            placeholder="请输入导出路径"
                            style={{ width: '100%' }}
                        />
                        <div style={{ fontSize: 11, color: '#999', marginTop: 4 }}>
                            导出的文件将保存到此目录
                        </div>
                    </div>

                    <div style={{ marginBottom: 8 }}>
                        <Checkbox
                            defaultChecked={true}
                            onChange={(e) => { usePlaceholder = e.target.checked; }}
                        >
                            为没有匹配的图片生成红色占位图
                        </Checkbox>
                    </div>
                    <div>
                        <Checkbox
                            defaultChecked={false}
                            onChange={(e) => { onlyConfirmed = e.target.checked; }}
                        >
                            只导出已确认的过滤条件
                        </Checkbox>
                    </div>
                </div>
            ),
            okText: '确认导出',
            cancelText: '取消',
            onOk: async () => {
                try {
                    setIsExporting(true);
                    setExportProgress(null); // 清除之前的进度
                    exportPathRef.current = exportPath; // 保存到 ref
                    console.log('Export path saved to ref:', exportPath);
                    await exportProject(projectId, usePlaceholder, onlyConfirmed, exportPath);
                    message.success('导出已在后台开始');
                    // Update the output path after successful export start
                    if (exportPath) {
                        setProjectOutputPath(exportPath);
                    }
                    // Start polling for progress
                    pollExportProgress();
                } catch (e: any) {
                    message.error('导出启动失败: ' + (e.message || '未知错误'));
                    setIsExporting(false);
                    setExportProgress(null);
                }
            }
        });
    };

    // Poll export progress
    const pollExportProgress = async () => {
        const interval = setInterval(async () => {
            try {
                const progress = await getExportProgress(projectId);
                setExportProgress(progress);

                // Stop polling if export is complete
                if (progress.processed >= progress.total && progress.total > 0) {
                    clearInterval(interval);

                    // 延迟1秒后显示完成对话框
                    setTimeout(() => {
                        setIsExporting(false);

                        // 从 ref 获取导出路径（确保使用用户输入的路径）
                        const displayPath = exportPathRef.current || projectOutputPath || '未知路径';
                        console.log('Displaying export completion. Path from ref:', exportPathRef.current, 'Display path:', displayPath);

                        // 显示导出完成对话框
                        Modal.success({
                            title: '导出完成',
                            width: 600,
                            content: (
                                <div>
                                    <p style={{ marginBottom: 12 }}>图片导出已完成！</p>
                                    <div style={{ background: '#f5f5f5', padding: 12, borderRadius: 4, wordBreak: 'break-all' }}>
                                        <div style={{ fontSize: 12, color: '#666', marginBottom: 4 }}>导出路径：</div>
                                        <div style={{ fontFamily: 'monospace', fontSize: 13 }}>{displayPath}</div>
                                    </div>
                                    <p style={{ marginTop: 12, fontSize: 12, color: '#666' }}>
                                        共处理 {progress.total} 个文件
                                    </p>
                                </div>
                            ),
                            okText: '知道了'
                        });

                        setExportProgress(null);
                    }, 1000);
                }
            } catch (e) {
                console.error('Failed to fetch export progress:', e);
                clearInterval(interval);
                message.error('获取导出进度失败');
                setIsExporting(false);
                setExportProgress(null);
            }
        }, 1000);

        // Stop polling after 30 minutes
        setTimeout(() => {
            clearInterval(interval);
            if (exportProgress && exportProgress.processed < exportProgress.total) {
                message.warning('导出超时，请检查服务状态');
            }
            setIsExporting(false);
            setExportProgress(null);
        }, 30 * 60 * 1000);
    };

    // Open candidate selection modal
    const openCandidateModal = (
        sourceId: number,
        targetId: number,
        targetName: string,
        candidates: any[],
        sourceImage: { path: string, width: number, height: number },
        currentSelectedId?: number
    ) => {
        setCurrentSourceId(sourceId);
        setCurrentTargetId(targetId);
        setCurrentTargetName(targetName);
        setCurrentCandidates(candidates);
        setCurrentSourceImage(sourceImage);
        setSelectedCandidateInModal(currentSelectedId || (candidates.length > 0 ? candidates[0].id : null));
        setModalVisible(true);
    };

    // Handle modal OK - save selection
    const handleModalOk = async () => {
        if (!currentSourceId || !currentTargetId) return;

        try {
            if (selectedCandidateInModal === -1) {
                // Selected "No Match"
                await markNoMatch(projectId, currentSourceId, currentTargetId);
                message.success('已标记为无匹配');
            } else if (selectedCandidateInModal) {
                // Selected a specific candidate
                await selectCandidate(projectId, currentSourceId, currentTargetId, selectedCandidateInModal);
                message.success('已选择匹配项');
            }

            // Update local state
            setTableData(prev => prev.map(item => {
                if (item.source_file_id === currentSourceId) {
                    const newTargetSelections = { ...item.target_selections };
                    newTargetSelections[currentTargetName] = selectedCandidateInModal === -1
                        ? { no_match: true, selected_candidate_id: undefined }
                        : { no_match: false, selected_candidate_id: selectedCandidateInModal };
                    return { ...item, target_selections: newTargetSelections };
                }
                return item;
            }));

            setModalVisible(false);
        } catch (e) {
            message.error('操作失败');
        }
    };

    // Columns definition
    const targetKeys = useMemo(() => {
        return projectTargets.map(t => t.name);
    }, [projectTargets]);

    const columns: any[] = [
        {
            title: '确认',
            key: 'confirmation',
            width: 50,
            fixed: 'left',
            align: 'center',
            render: (_: any, record: TableItem) => {
                if (record.confirmed) {
                    return (
                        <CheckCircleFilled
                            style={{
                                fontSize: 18,
                                color: '#52c41a',
                                cursor: 'pointer'
                            }}
                            onClick={() => handleConfirm(record, false)}
                            title="点击取消确认"
                        />
                    );
                }
                return null;
            }
        },
        {
            title: '源图片',
            key: 'source',
            width: 180,
            fixed: 'left',
            align: 'center',
            render: (_: any, record: TableItem) => {
                const fileName = record.source.relative.split('/').pop() || record.source.relative;
                return (
                    <Space direction="vertical" align="center" style={{ width: '100%' }}>
                        <div
                            style={{
                                width: 140,
                                height: 140,
                                backgroundImage: 'linear-gradient(45deg, #ccc 25%, transparent 25%), linear-gradient(-45deg, #ccc 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #ccc 75%), linear-gradient(-45deg, transparent 75%, #ccc 75%)',
                                backgroundSize: '20px 20px',
                                backgroundPosition: '0 0, 0 10px, 10px -10px, -10px 0px',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                padding: 4
                            }}
                        >
                            <Image
                                src={record.source.thumb_url}
                                style={{
                                    maxWidth: '100%',
                                    maxHeight: '100%',
                                    objectFit: 'contain'
                                }}
                                preview={{
                                    mask: '查看'
                                }}
                            />
                        </div>
                        <div style={{ fontSize: 12, marginTop: 6, wordBreak: 'break-all', padding: '0 4px', textAlign: 'center', maxWidth: '100%' }}>
                            {fileName}
                        </div>
                        <div style={{ textAlign: 'center', fontSize: 11, color: '#888' }}>
                            {record.source.width} × {record.source.height}
                        </div>
                    </Space>
                );
            }
        },
        ...targetKeys.map(key => {
            const target = projectTargets.find(t => t.name === key);
            return {
                title: key,
                key: key,
                width: 180,
                align: 'center',
                render: (_: any, record: TableItem) => {
                    const candidates = record.candidates[key] || [];
                    const targetSelection = record.target_selections[key];

                    // Check if no match is marked
                    if (targetSelection?.no_match) {
                        return (
                            <Space direction="vertical" align="center" style={{ width: '100%' }}>
                                <div
                                    style={{
                                        width: 140,
                                        height: 140,
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        border: '2px dashed #ccc'
                                    }}
                                >
                                    <span style={{ color: '#999' }}>无匹配</span>
                                </div>
                                {candidates.length > 0 && (
                                    <a onClick={() => openCandidateModal(
                                        record.source_file_id,
                                        target!.id,
                                        key,
                                        candidates,
                                        { path: record.source.thumb_url, width: record.source.width || 0, height: record.source.height || 0 },
                                        undefined
                                    )}>
                                        重新选择
                                    </a>
                                )}
                            </Space>
                        );
                    }

                    // No candidates available - this should never happen with adaptive matching
                    if (!Array.isArray(candidates) || candidates.length === 0) {
                        return (
                            <Space direction="vertical" align="center" style={{ width: '100%' }}>
                                <div
                                    style={{
                                        width: 140,
                                        height: 140,
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        border: '1px solid #ddd',
                                    }}
                                >
                                    <span style={{ color: '#ccc' }}>无候选项</span>
                                </div>
                                <Button
                                    size="small"
                                    danger
                                    onClick={async () => {
                                        try {
                                            await markNoMatch(projectId, record.source_file_id, target!.id);
                                            setTableData(prev => prev.map(item => {
                                                if (item.source_file_id === record.source_file_id) {
                                                    const newTargetSelections = { ...item.target_selections };
                                                    newTargetSelections[key] = { no_match: true, selected_candidate_id: undefined };
                                                    return { ...item, target_selections: newTargetSelections };
                                                }
                                                return item;
                                            }));
                                            message.success('已标记为无匹配');
                                        } catch (e) {
                                            message.error('操作失败');
                                        }
                                    }}
                                >
                                    标记无匹配
                                </Button>
                            </Space>
                        );
                    }

                    // Determine which candidate to display
                    let displayCand = candidates[0];
                    if (targetSelection?.selected_candidate_id) {
                        const found = candidates.find(c => c.id === targetSelection.selected_candidate_id);
                        if (found) displayCand = found;
                    }

                    if (!displayCand) return <span>错误</span>;

                    return (
                        <Space direction="vertical" align="center" style={{ width: '100%' }}>
                            <div
                                style={{
                                    width: 140,
                                    height: 140,
                                    backgroundImage: 'linear-gradient(45deg, #ccc 25%, transparent 25%), linear-gradient(-45deg, #ccc 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #ccc 75%), linear-gradient(-45deg, transparent 75%, #ccc 75%)',
                                    backgroundSize: '20px 20px',
                                    backgroundPosition: '0 0, 0 10px, 10px -10px, -10px 0px',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    padding: 4,
                                    border: '1px solid #ddd'
                                }}
                            >
                                <Image
                                    src={`/api/image?path=${encodeURIComponent(displayCand.path)}`}
                                    style={{
                                        maxWidth: '100%',
                                        maxHeight: '100%',
                                        objectFit: 'contain'
                                    }}
                                    preview={{
                                        mask: '查看'
                                    }}
                                />
                            </div>
                            <div style={{ textAlign: 'center', fontSize: 11, width: '100%' }}>
                                <div>相似度: {displayCand.similarity.toFixed(2)}%</div>
                                <div style={{ color: '#888' }}>{displayCand.width} × {displayCand.height}</div>
                                <Space direction="horizontal" size={4} style={{ marginTop: 4, justifyContent: 'center' }}>
                                    {candidates.length > 1 && (
                                        <Button
                                            size="small"
                                            type="link"
                                            style={{ padding: '0 4px', height: 'auto' }}
                                            onClick={() => openCandidateModal(
                                                record.source_file_id,
                                                target!.id,
                                                key,
                                                candidates,
                                                { path: record.source.thumb_url, width: record.source.width || 0, height: record.source.height || 0 },
                                                targetSelection?.selected_candidate_id
                                            )}
                                        >
                                            候选 {candidates.length} 个
                                        </Button>
                                    )}
                                    <Button
                                        size="small"
                                        danger
                                        type="text"
                                        onClick={async () => {
                                            try {
                                                await markNoMatch(projectId, record.source_file_id, target!.id);
                                                setTableData(prev => prev.map(item => {
                                                    if (item.source_file_id === record.source_file_id) {
                                                        const newTargetSelections = { ...item.target_selections };
                                                        newTargetSelections[key] = { no_match: true, selected_candidate_id: undefined };
                                                        return { ...item, target_selections: newTargetSelections };
                                                    }
                                                    return item;
                                                }));
                                                message.success('已标记为无匹配');
                                            } catch (e) {
                                                message.error('操作失败');
                                            }
                                        }}
                                    >
                                        标记无匹配
                                    </Button>
                                </Space>
                            </div>
                        </Space>
                    );
                }
            };
        }),
        {
            title: '操作',
            key: 'action',
            fixed: 'right',
            width: 80,
            align: 'center',
            render: (_: any, record: TableItem) => (
                <Checkbox
                    checked={record.confirmed}
                    onChange={e => handleConfirm(record, e.target.checked)}
                >
                    确认
                </Checkbox>
            )
        }
    ];

    return (
        <div style={{ padding: 16, height: 'calc(100vh - 64px)', display: 'flex', flexDirection: 'column' }}>
            <div style={{ marginBottom: 16, display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
                <Input
                    placeholder="搜索..."
                    style={{ width: 180 }}
                    value={searchText}
                    onChange={e => setSearchText(e.target.value)}
                    allowClear
                />
                <InputNumber placeholder="最小宽度" style={{ width: 100 }} min={0} value={minWidth} onChange={val => setMinWidth(val)} />
                <InputNumber placeholder="最小高度" style={{ width: 100 }} min={0} value={minHeight} onChange={val => setMinHeight(val)} />
                <Select
                    value={orientationFilter === 'all' ? undefined : orientationFilter}
                    style={{ width: 120 }}
                    onChange={val => setOrientationFilter(val as any)}
                    placeholder="方向"
                    allowClear
                    onClear={() => setOrientationFilter('all')}
                >
                    <Option value="square">正方形</Option>
                    <Option value="landscape">横向</Option>
                    <Option value="portrait">纵向</Option>
                </Select>
                <Select
                    value={confirmFilter === 'all' ? undefined : confirmFilter}
                    style={{ width: 100 }}
                    onChange={val => setConfirmFilter(val as any)}
                    placeholder="状态"
                    allowClear
                    onClear={() => setConfirmFilter('all')}
                >
                    <Option value="confirmed">已完成</Option>
                    <Option value="unconfirmed">待处理</Option>
                </Select>
                <Button onClick={() => {
                    setSearchText('');
                    setMinWidth(null);
                    setMinHeight(null);
                    setOrientationFilter('all');
                    setConfirmFilter('all');
                }}>
                    重置筛选
                </Button>

                <Space>
                    <Button icon={<CheckSquareOutlined />} onClick={() => handleBatchConfirm(true)} disabled={selectedRowKeys.length === 0}>
                        批量确认
                    </Button>
                    <Button icon={<StopOutlined />} danger onClick={() => handleBatchConfirm(false)} disabled={selectedRowKeys.length === 0}>
                        批量取消
                    </Button>
                </Space>

                <div style={{ flex: 1 }} />

                {/* Export Button or Progress */}
                {isExporting && exportProgress ? (
                    <div style={{ width: 300 }}>
                        <div style={{ marginBottom: 4, display: 'flex', justifyContent: 'space-between', fontSize: 12, color: '#666' }}>
                            <span>导出进度</span>
                            <span>{exportProgress.processed} / {exportProgress.total}</span>
                        </div>
                        <Progress
                            percent={exportProgress.total > 0 ? Math.round((exportProgress.processed / exportProgress.total) * 100) : 0}
                            status="active"
                            strokeColor={{
                                '0%': '#108ee9',
                                '100%': '#87d068',
                            }}
                        />
                        <div style={{ fontSize: 11, color: '#999', marginTop: 4, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {exportProgress.current || '准备中...'}
                        </div>
                    </div>
                ) : (
                    <Button type="primary" icon={<ExportOutlined />} onClick={handleExport} disabled={isExporting}>
                        导出
                    </Button>
                )}
            </div>


            <div style={{ flex: 1, overflow: 'auto' }}>
                <Table
                    dataSource={filteredData}
                    columns={columns}
                    rowKey="source_file_id"
                    loading={loading}
                    pagination={{
                        current: currentPage,
                        pageSize: pageSize,
                        showSizeChanger: true,
                        pageSizeOptions: ['10', '20', '50', '100'],
                        onChange: (page, size) => {
                            setCurrentPage(page);
                            if (size !== pageSize) {
                                setPageSize(size);
                                setCurrentPage(1);
                            }
                        },
                        showTotal: (total) => `共 ${total} 条`
                    }}
                    scroll={{ y: 'calc(100vh - 200px)' }}
                    rowSelection={{
                        selectedRowKeys,
                        onChange: (keys) => setSelectedRowKeys(keys)
                    }}
                />
            </div>

            <Modal
                title={`选择最佳匹配 - ${currentTargetName}`}
                open={modalVisible}
                onOk={handleModalOk}
                onCancel={() => setModalVisible(false)}
                width={1100}
                okText="确定"
                cancelText="取消"
            >
                <div style={{ display: 'flex', gap: 16 }}>
                    {/* 左侧：源图片 - 固定不动 */}
                    <div style={{ width: 280, flexShrink: 0 }}>
                        <div style={{
                            padding: 12,
                            background: '#fafafa',
                            borderRadius: 4,
                            border: '1px solid #d9d9d9'
                        }}>
                            <div style={{
                                fontWeight: 500,
                                marginBottom: 12,
                                fontSize: 14,
                                color: '#262626'
                            }}>
                                源图片
                            </div>
                            {currentSourceImage && (
                                <>
                                    <div
                                        style={{
                                            width: '100%',
                                            height: 200,
                                            backgroundImage: 'linear-gradient(45deg, #f0f0f0 25%, transparent 25%), linear-gradient(-45deg, #f0f0f0 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #f0f0f0 75%), linear-gradient(-45deg, transparent 75%, #f0f0f0 75%)',
                                            backgroundSize: '20px 20px',
                                            backgroundPosition: '0 0, 0 10px, 10px -10px, -10px 0px',
                                            display: 'flex',
                                            alignItems: 'center',
                                            justifyContent: 'center',
                                            border: '1px solid #d9d9d9',
                                            borderRadius: 4,
                                            overflow: 'hidden',
                                            marginBottom: 12
                                        }}
                                    >
                                        <Image
                                            src={currentSourceImage.path}
                                            style={{
                                                maxWidth: '100%',
                                                maxHeight: '100%',
                                                objectFit: 'contain'
                                            }}
                                            preview={{
                                                mask: '预览'
                                            }}
                                        />
                                    </div>
                                    <div style={{ textAlign: 'center', fontSize: 12, color: '#8c8c8c' }}>
                                        尺寸: {currentSourceImage.width} × {currentSourceImage.height}
                                    </div>
                                </>
                            )}
                        </div>
                    </div>

                    {/* 右侧：候选列表 */}
                    <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
                        <Radio.Group
                            onChange={e => setSelectedCandidateInModal(e.target.value)}
                            value={selectedCandidateInModal}
                            style={{ width: '100%', display: 'flex', flexDirection: 'column', height: '100%' }}
                        >
                            {/* 无匹配选项 - 固定在顶部 */}
                            <List size="small" bordered style={{ flexShrink: 0 }}>
                                <List.Item
                                    style={{
                                        padding: '12px',
                                        cursor: 'pointer',
                                        backgroundColor: selectedCandidateInModal === -1 ? '#fff1f0' : 'transparent'
                                    }}
                                    onClick={() => setSelectedCandidateInModal(-1)}
                                >
                                    <Radio value={-1} style={{ width: '100%' }}>
                                        <div style={{ padding: '4px 0', color: '#ff4d4f', fontWeight: 500 }}>
                                            无匹配
                                        </div>
                                    </Radio>
                                </List.Item>
                            </List>

                            {/* 候选图片列表 - 可滚动 */}
                            <div style={{ flex: 1, overflowY: 'auto', marginTop: 12, maxHeight: 'calc(70vh - 80px)' }}>
                                <List
                                    dataSource={currentCandidates}
                                    size="small"
                                    bordered
                                    renderItem={(item, index) => (
                                        <List.Item
                                            style={{
                                                padding: '12px',
                                                cursor: 'pointer',
                                                backgroundColor: selectedCandidateInModal === item.id ? '#e6f7ff' : 'transparent'
                                            }}
                                            onClick={() => setSelectedCandidateInModal(item.id)}
                                        >
                                            <div style={{ display: 'flex', alignItems: 'center', width: '100%', gap: 16 }}>
                                                <Radio value={item.id} />
                                                <div style={{
                                                    width: 140,
                                                    height: 140,
                                                    flexShrink: 0,
                                                    backgroundImage: 'linear-gradient(45deg, #f0f0f0 25%, transparent 25%), linear-gradient(-45deg, #f0f0f0 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #f0f0f0 75%), linear-gradient(-45deg, transparent 75%, #f0f0f0 75%)',
                                                    backgroundSize: '20px 20px',
                                                    backgroundPosition: '0 0, 0 10px, 10px -10px, -10px 0px',
                                                    display: 'flex',
                                                    alignItems: 'center',
                                                    justifyContent: 'center',
                                                    border: '1px solid #d9d9d9',
                                                    borderRadius: 4,
                                                    overflow: 'hidden'
                                                }}>
                                                    <Image
                                                        src={`/api/image?path=${encodeURIComponent(item.path)}`}
                                                        style={{
                                                            maxWidth: '100%',
                                                            maxHeight: '100%',
                                                            objectFit: 'contain'
                                                        }}
                                                        preview={{
                                                            mask: '预览'
                                                        }}
                                                    />
                                                </div>
                                                <div style={{ flex: 1, minWidth: 0 }}>
                                                    <div style={{
                                                        display: 'flex',
                                                        justifyContent: 'space-between',
                                                        alignItems: 'center'
                                                    }}>
                                                        <span style={{
                                                            fontWeight: 500,
                                                            fontSize: 14,
                                                            color: item.similarity >= 80 ? '#52c41a' : item.similarity >= 60 ? '#faad14' : '#ff4d4f'
                                                        }}>
                                                            #{index + 1} - 相似度: {item.similarity.toFixed(2)}%
                                                        </span>
                                                        <span style={{ fontSize: 13, color: '#8c8c8c' }}>
                                                            {item.width} × {item.height}
                                                        </span>
                                                    </div>
                                                </div>
                                            </div>
                                        </List.Item>
                                    )}
                                />
                            </div>
                        </Radio.Group>
                    </div>
                </div>
            </Modal>
        </div>
    );
};

export default QuickCompare;
