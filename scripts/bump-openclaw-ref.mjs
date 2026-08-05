import fs from "node:fs";

const owner = "openclaw";
const repo = "openclaw";
const token = process.env.GITHUB_TOKEN;
if (!token) {
  console.error("Missing GITHUB_TOKEN");
  process.exit(2);
}

async function gh(path) {
  const url = `https://api.github.com${path}`;
  const res = await fetch(url, {
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "user-agent": "clawdbot-railway-template-bot",
    },
  });
  if (!res.ok) {
    throw new Error(`GitHub API ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

function readCurrentTag(dockerfile) {
  const m = dockerfile.match(/\nARG OPENCLAW_GIT_REF=([^\n]+)\n/);
  return m ? m[1].trim() : null;
}

function replaceTag(dockerfile, next) {
  const re = /\nARG OPENCLAW_GIT_REF=([^\n]+)\n/;
  if (!re.test(dockerfile)) throw new Error("Could not find OPENCLAW_GIT_REF line");
  return dockerfile.replace(re, `\nARG OPENCLAW_GIT_REF=${next}\n`);
}

// Emit a GitHub Actions step output (no-op when run locally).
function setOutput(key, value) {
  const f = process.env.GITHUB_OUTPUT;
  if (f) fs.appendFileSync(f, `${key}=${value}\n`);
}

const latest = await gh(`/repos/${owner}/${repo}/releases/latest`);
const latestTag = latest.tag_name;
if (!latestTag) throw new Error("No tag_name in latest release response");
const notesUrl =
  latest.html_url || `https://github.com/${owner}/${repo}/releases/tag/${latestTag}`;

const dockerPath = "Dockerfile";
const docker = fs.readFileSync(dockerPath, "utf8");
const currentTag = readCurrentTag(docker);
if (!currentTag) throw new Error("Could not parse current OPENCLAW_GIT_REF");

console.log(`current=${currentTag} latest=${latestTag}`);
setOutput("current", currentTag);
setOutput("latest", latestTag);
setOutput("notes_url", notesUrl);

if (currentTag === latestTag) {
  console.log("No update needed.");
  setOutput("updated", "false");
  process.exit(0);
}

fs.writeFileSync(dockerPath, replaceTag(docker, latestTag));
setOutput("updated", "true");
console.log(`Updated ${dockerPath} to ${latestTag}`);
