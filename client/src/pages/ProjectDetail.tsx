import React, { useEffect } from 'react';
import { Layout, Menu, Typography, Tag, Spin, Button } from 'antd';
import { Outlet, useParams, useNavigate, useLocation } from 'react-router-dom';
import { useAtom } from 'jotai';
import { currentProjectAtom } from '../store';
import { getProject } from '../api';
import { DashboardOutlined } from '@ant-design/icons';

const { Sider, Content } = Layout;
const { Title, Text } = Typography;

const ProjectDetail: React.FC = () => {
    const { id } = useParams<{ id: string }>();
    const [project, setProject] = useAtom(currentProjectAtom);
    const navigate = useNavigate();
    const location = useLocation();

    useEffect(() => {
        if (id) {
            getProject(Number(id)).then(setProject).catch(console.error);
        }
    }, [id, setProject]);

    if (!project) return <Spin size="large" style={{ margin: 50 }} />;

    // 状态翻译
    const getStatusText = (status: string) => {
        const statusMap: Record<string, string> = {
            'pending': '待处理',
            'indexing': '索引中',
            'indexed': '已索引',
            'comparing': '比较中',
            'processing': '处理中',
            'scanned': '已扫描',
            'completed': '已完成',
            'error': '错误'
        };
        return statusMap[status] || status;
    };

    const getStatusColor = (status: string) => {
        if (status === 'completed') return 'success';
        if (status === 'error') return 'error';
        if (status === 'processing' || status === 'comparing' || status === 'indexing') return 'processing';
        if (status === 'indexed' || status === 'scanned') return 'cyan';
        return 'default';
    };

    return (
        <Layout style={{ minHeight: '100vh' }}>
            <Sider width={250} theme="light" style={{ borderRight: '1px solid #f0f0f0' }}>
                <div style={{ padding: 16 }}>
                    <Title level={4}>Look Alike</Title>
                    <div style={{ marginBottom: 16 }}>
                        <Text strong>{project.name}</Text>
                        <br />
                        <Tag color={getStatusColor(project.status)}>{getStatusText(project.status)}</Tag>
                    </div>
                    {project.stats && (
                        <div style={{ fontSize: 12, color: '#888' }}>
                            文件: {project.stats.processed} / {project.stats.total_files}
                        </div>
                    )}
                </div>
                <div style={{ padding: '0 16px', marginBottom: 16 }}>
                    <Button block onClick={() => navigate('/projects')}>返回项目列表</Button>
                </div>
                <Menu
                    mode="inline"
                    selectedKeys={[location.pathname]}
                    items={[
                        {
                            key: `/projects/${id}/compare`,
                            icon: <DashboardOutlined />,
                            label: '快速对比',
                            onClick: () => navigate(`/projects/${id}/compare`)
                        }
                    ]}
                />
            </Sider>
            <Layout>
                <Content style={{ padding: 0, background: '#fff' }}>
                    <Outlet />
                </Content>
            </Layout>
        </Layout>
    );
};

export default ProjectDetail;
