{
  "ignition": {
    "version": "3.2.0"
  },
  "passwd": {
    "users": [
      {
        "name": "root",
        "passwordHash": "$y$j9T$PPGS2ZmcEwK9Rva6ijffv.$FfSLRBTa9rctOyzshG6s77Gasi8pXaiInQ635D9TJZ5",
        "sshAuthorizedKeys": [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJ8JbonZgkET9Da28JR0heMMFsQSEpjbltHoRNMKa1ccjccQenpbvWW4hzLLhUWx8UQEa6ia1MrLAjyQt14rEd+AUgkhH/J9kAYqjwd8uhgP/W1/gDWzQTteS2bMvyVgezE5xk//RuFz4WNjHPIAFh9mjhSIkPOztKC7cDQDkTrDXP7sItPAkTFeqsaFJ6+uUXWhHjsZ2xUCvWw+uLzqEbr0sFk9VIslGvL0U8AjSVYMxqGxljKY51zAW8xAX0ljStO8zthJejuiJvVpEINxHb+PY4RBOomI+DHSsqALFE56cUd6Ft5BvI+b60WrM7nCZtkINeNrOGiGlvsoYuV92NsdzU6k91nOoBp1REFqoWBKunbL2cNAgCoYE/ECzSlId/8MwTCMKZ57ru7NNvUQwng6cNgjIrgjW3f0y4QM84F008KUzfUUDOGC1lWm8Eu5Dn3xbWH47JW4lzbR6v22hFmIoMWGndH+YRWbgAG8kmaYjg/1xqHngK/WtDgzbDtR8= george@Georgioss-Mini.home",
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4SrYkfM8Xu/9cFpqIOb8Y4OJ3WyPYJRB1zMOoTPJQN george@Georgioss-MacBook-Pro.local"
        ]
      }
    ]
  },
  "storage": {
    "files": [
      {
        "filesystem": "root",
        "path": "/etc/hostname",
        "mode": 420,
        "overwrite": true,
        "contents": {
          "source": "data:,HOST"
        }
      },
      {
        "path": "/etc/NetworkManager/conf.d/noauto.conf",
        "mode": 420,
        "overwrite": true,
        "contents": {
          "source": "data:text/plain;charset=utf-8;base64,W21haW5dCiMgRG8gbm90IGRvIGF1dG9tYXRpYyAoREhDUC9TTEFBQykgY29uZmlndXJhdGlvbiBvbiBldGhlcm5ldCBkZXZpY2VzCiMgd2l0aCBubyBvdGhlciBtYXRjaGluZyBjb25uZWN0aW9ucy4Kbm8tYXV0by1kZWZhdWx0PSoK",
          "human_read": "[main]\n# Do not do automatic (DHCP/SLAAC) configuration on ethernet devices\n# with no other matching connections.\nno-auto-default=*\n"
        }
      }
    ]
  }
}
