-- Voice Interactions Table
CREATE TABLE voice_interactions (
    id SERIAL PRIMARY KEY,
    interaction_id VARCHAR(255) UNIQUE NOT NULL,
    session_id VARCHAR(255) NOT NULL,
    user_input TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    processing_time INTEGER,
    audio_format VARCHAR(50),
    audio_size INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Training Feedback Table
CREATE TABLE training_feedback (
    id SERIAL PRIMARY KEY,
    interaction_id VARCHAR(255) REFERENCES voice_interactions(interaction_id),
    feedback_score INTEGER CHECK (feedback_score >= 1 AND feedback_score <= 5),
    corrected_transcription TEXT,
    corrected_response TEXT,
    comments TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    feedback_requested_at TIMESTAMP,
    feedback_submitted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Model Versions Table
CREATE TABLE model_versions (
    id SERIAL PRIMARY KEY,
    model_id VARCHAR(255) UNIQUE NOT NULL,
    base_model VARCHAR(255) NOT NULL,
    training_samples INTEGER,
    validation_accuracy DECIMAL(5,4),
    status VARCHAR(50) DEFAULT 'training',
    dataset_id VARCHAR(255),
    deployment_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Training Jobs Table
CREATE TABLE training_jobs (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(255) UNIQUE NOT NULL,
    model_version_id INTEGER REFERENCES model_versions(id),
    job_status VARCHAR(50) DEFAULT 'queued',
    training_config JSONB,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Performance Metrics Table
CREATE TABLE performance_metrics (
    id SERIAL PRIMARY KEY,
    model_version_id INTEGER REFERENCES model_versions(id),
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(10,6),
    measurement_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX idx_voice_interactions_session_id ON voice_interactions(session_id);
CREATE INDEX idx_voice_interactions_created_at ON voice_interactions(created_at);
CREATE INDEX idx_training_feedback_interaction_id ON training_feedback(interaction_id);
CREATE INDEX idx_training_feedback_status ON training_feedback(status);
CREATE INDEX idx_model_versions_status ON model_versions(status);
CREATE INDEX idx_performance_metrics_model_version_id ON performance_metrics(model_version_id);
