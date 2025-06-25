# n8n-voice-ai
n8n Voice AI Agent with Continuous Learning

## **Quick Setup for Your Proxmox VM:**

1. **Create the directory structure:**
```bash
sudo mkdir -p /opt/n8n-voice-ai/{data,config,backups}
cd /opt/n8n-voice-ai
```

2. **Copy the corrected workflows** from the artifact above

3. **Import order:**
   - First: Logging Sub-Workflow 
   - Second: Feedback Collection Sub-Workflow
   - Third: Continuous Learning Pipeline
   - Fourth: Main Workflow

4. **Update environment variables** with the actual workflow IDs after import

The corrected JSON should now import cleanly without any "propertyValues" or "property option" errors. Each workflow uses the current n8n parameter structures and should work with your Docker/Proxmox setup.
