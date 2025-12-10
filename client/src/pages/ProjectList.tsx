import React, { useEffect, useState } from 'react';
import { Table, Button, Modal, Form, Input, Space, Tag, message } from 'antd';
import { PlusOutlined, DeleteOutlined, MinusCircleOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
import { useAtom } from 'jotai';
import { projectsAtom } from '../store';
import { getProjects, createProject, deleteProject } from '../api';
import type { Project } from '../types';

const ProjectList: React.FC = () => {
    const [projects, setProjects] = useAtom(projectsAtom);
    const [loading, setLoading] = useState(false);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [form] = Form.useForm();
    const navigate = useNavigate();
    const [currentTime, setCurrentTime] = useState(Date.now());

    const fetchProjects = async () => {
        try {
            const data = await getProjects();
            // Ensure projects is array
            setProjects(data.projects || []);
        } catch (e) {
            console.error(e);
        }
    };

    useEffect(() => {
        fetchProjects();
        const interval = setInterval(fetchProjects, 30000);
        return () => clearInterval(interval);
    }, [setProjects]);

    // Update current time every second for live duration calculation
    useEffect(() => {
        const timer = setInterval(() => {
            setCurrentTime(Date.now());
        }, 1000);
        return () => clearInterval(timer);
    }, []);

    const handleCreate = async (values: any) => {
        try {
            setLoading(true);
            await createProject(values);
            message.success('项目已创建并开始处理');
            setIsModalOpen(false);
            form.resetFields();
            fetchProjects();
        } catch (e) {
            message.error('创建项目失败');
        } finally {
            setLoading(false);
        }
    };

    const handleDelete = async (id: number, name: string) => {
        Modal.confirm({
            title: '确认删除',
            content: `确定要删除项目"${name}"吗？此操作将删除所有相关数据且无法恢复。`,
            okText: '确认删除',
            okType: 'danger',
            cancelText: '取消',
            onOk: async () => {
                try {
                    await deleteProject(id);
                    message.success('项目已删除');
                    fetchProjects();
                } catch (e) {
                    message.error('删除失败');
                }
            }
        });
    };

    const columns = [
        {
            title: '活动名称',
            dataIndex: 'name',
            key: 'name',
        },
        {
            title: '索引状态',
            dataIndex: 'status',
            key: 'status',
            render: (status: string) => {
                let color = 'default';
                let text = '未知';
                if (status === 'pending') { color = 'default'; text = '待处理'; }
                if (status === 'indexing') { color = 'processing'; text = '索引中'; }
                if (status === 'indexed') { color = 'cyan'; text = '已索引'; }
                if (status === 'comparing') { color = 'processing'; text = '比较中'; }
                if (status === 'processing') { color = 'processing'; text = '处理中'; }
                if (status === 'scanned') { color = 'cyan'; text = '已扫描'; }
                if (status === 'completed') { color = 'success'; text = '已完成'; }
                if (status === 'error') { color = 'error'; text = '错误'; }
                return <Tag color={color}>{text}</Tag>;
            }
        },
        {
            title: '确认进度',
            key: 'confirmation',
            align: 'center' as const,
            render: (_: any, record: Project) => {
                if (record.confirmation_stats) {
                    const { confirmed, total } = record.confirmation_stats;
                    const percentage = total > 0 ? ((confirmed / total) * 100).toFixed(0) : '0';
                    return (
                        <span>
                            <span style={{ fontWeight: 'bold' }}>{confirmed}</span>
                            <span style={{ color: '#888' }}> / </span>
                            <span>{total}</span>
                            <span style={{ fontSize: 11, color: '#999', marginLeft: 8 }}>
                                ({percentage}%)
                            </span>
                        </span>
                    );
                }
                return '-';
            }
        },
        {
            title: '处理时长',
            key: 'time',
            render: (_: any, record: Project) => {
                if (record.started_at && record.ended_at) {
                    // 已完成：显示总耗时
                    const diff = new Date(record.ended_at).getTime() - new Date(record.started_at).getTime();
                    const seconds = Math.floor(diff / 1000);
                    if (seconds < 60) {
                        return `${seconds}秒`;
                    } else if (seconds < 3600) {
                        const minutes = Math.floor(seconds / 60);
                        const remainingSeconds = seconds % 60;
                        return `${minutes}分${remainingSeconds}秒`;
                    } else {
                        const hours = Math.floor(seconds / 3600);
                        const minutes = Math.floor((seconds % 3600) / 60);
                        return `${hours}小时${minutes}分`;
                    }
                }
                // 处理中的所有状态：indexing, indexed, comparing, processing
                const processingStatuses = ['indexing', 'indexed', 'comparing', 'processing'];
                if (processingStatuses.includes(record.status) && record.started_at) {
                    // 处理中：实时显示已运行时间
                    const diff = currentTime - new Date(record.started_at).getTime();
                    const seconds = Math.floor(diff / 1000);
                    if (seconds < 60) {
                        return `${seconds}秒`;
                    } else if (seconds < 3600) {
                        const minutes = Math.floor(seconds / 60);
                        const remainingSeconds = seconds % 60;
                        return `${minutes}分${remainingSeconds}秒`;
                    } else {
                        const hours = Math.floor(seconds / 3600);
                        const minutes = Math.floor((seconds % 3600) / 60);
                        return `${hours}小时${minutes}分`;
                    }
                }
                return '-';
            }
        },
        {
            title: '操作',
            key: 'action',
            width: 180,
            render: (_: any, record: Project) => (
                <Space>
                    <Button type="primary" onClick={() => navigate(`/projects/${record.id}`)}>进入</Button>
                    <Button danger icon={<DeleteOutlined />} onClick={() => handleDelete(record.id, record.name)}>
                        删除项目
                    </Button>
                </Space>
            )
        }
    ];

    return (
        <div style={{ padding: 24 }}>
            <div style={{ marginBottom: 16, display: 'flex', justifyContent: 'space-between' }}>
                <h1>项目列表</h1>
                <Button type="primary" icon={<PlusOutlined />} onClick={() => setIsModalOpen(true)}>
                    新建项目
                </Button>
            </div>

            <Table dataSource={projects} columns={columns} rowKey="id" />

            <Modal
                title="创建新项目"
                open={isModalOpen}
                onCancel={() => setIsModalOpen(false)}
                onOk={() => form.submit()}
                confirmLoading={loading}
                width={800}
                okText="确定"
                cancelText="取消"
            >
                <Form form={form} layout="vertical" onFinish={handleCreate}>
                    <Form.Item name="name" label="活动名称" rules={[{ required: true, message: '请输入活动名称' }]}>
                        <Input placeholder="请输入活动名称" />
                    </Form.Item>
                    <Form.Item name="source_path" label="源目录" rules={[{ required: true, message: '请输入源目录路径' }]}>
                        <Input placeholder="/绝对路径/到/源目录" />
                    </Form.Item>

                    <Form.List name="targets">
                        {(fields, { add, remove }) => (
                            <>
                                {fields.map(({ key, name, ...restField }) => (
                                    <Space key={key} style={{ display: 'flex', marginBottom: 8 }} align="baseline">
                                        <Form.Item
                                            {...restField}
                                            name={[name, 'name']}
                                            rules={[{ required: true, message: '请输入标签' }]}
                                        >
                                            <Input placeholder="标签/名称" />
                                        </Form.Item>
                                        <Form.Item
                                            {...restField}
                                            name={[name, 'path']}
                                            rules={[{ required: true, message: '请输入目标路径' }]}
                                            style={{ width: 400 }}
                                        >
                                            <Input placeholder="目标目录路径" />
                                        </Form.Item>
                                        <MinusCircleOutlined onClick={() => remove(name)} />
                                    </Space>
                                ))}
                                <Form.Item>
                                    <Button type="dashed" onClick={() => add()} block icon={<PlusOutlined />}>
                                        添加目标目录
                                    </Button>
                                </Form.Item>
                            </>
                        )}
                    </Form.List>
                </Form>
            </Modal>
        </div>
    );
};

export default ProjectList;
