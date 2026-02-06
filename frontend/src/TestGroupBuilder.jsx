import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import './TestBuilder.css';

const TestGroupBuilder = () => {
  const { id } = useParams();
  const navigate = useNavigate();
  const isEdit = !!id;

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    color: '#4CA9E9'
  });
  const [loading, setLoading] = useState(isEdit);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (isEdit) {
      loadTestGroup();
    }
  }, [id]);

  const loadTestGroup = async () => {
    setLoading(true);
    try {
      const response = await fetch(`http://localhost:3000/test-groups/${id}`);
      const data = await response.json();
      setFormData({
        name: data.test_group.name,
        description: data.test_group.description || '',
        color: data.test_group.color || '#4CA9E9'
      });
    } catch (error) {
      console.error('Error loading test group:', error);
      alert('Failed to load test group');
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field, value) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true);

    try {
      const url = isEdit 
        ? `http://localhost:3000/test-groups/${id}` 
        : 'http://localhost:3000/test-groups';
      const method = isEdit ? 'PUT' : 'POST';

      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ test_group: formData })
      });

      if (response.ok) {
        alert(isEdit ? 'Test group updated!' : 'Test group created!');
        navigate('/test-library');
      } else {
        const error = await response.json();
        alert('Error: ' + (error.errors?.join(', ') || 'Failed to save'));
      }
    } catch (error) {
      console.error('Error saving test group:', error);
      alert('Failed to save test group');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="test-builder-loading">Loading...</div>;
  }

  return (
    <div className="main-content">
      <div className="content-wrapper">
        <div className="content-inner">
          <div className="test-builder">
            <div className="test-builder-header">
              <h1>{isEdit ? 'Edit Test Group' : 'Create Test Group'}</h1>
              <button onClick={() => navigate('/test-library')} className="btn btn-secondary">
                Cancel
              </button>
            </div>

      <form onSubmit={handleSubmit} className="test-builder-form">
        <div className="form-section">
          <h2>Group Information</h2>
          
          <div className="form-group">
            <label>Group Name *</label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => handleChange('name', e.target.value)}
              required
              placeholder="e.g., SEO Tests"
            />
          </div>

          <div className="form-group">
            <label>Description</label>
            <textarea
              value={formData.description}
              onChange={(e) => handleChange('description', e.target.value)}
              placeholder="Brief description of this test group..."
              rows="3"
            />
          </div>

          <div className="form-group">
            <label>Group Color</label>
            <input
              type="color"
              value={formData.color}
              onChange={(e) => handleChange('color', e.target.value)}
            />
            <small>This color will be displayed in the test library sidebar</small>
          </div>
        </div>

        <div className="form-actions">
          <button type="button" onClick={() => navigate('/test-library')} className="btn btn-secondary">
            Cancel
          </button>
          <button type="submit" className="btn btn-primary" disabled={saving}>
            {saving ? 'Saving...' : (isEdit ? 'Update Group' : 'Create Group')}
          </button>
        </div>
      </form>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TestGroupBuilder;
