require "pathname"

RSpec.describe "the deployment documentation contract" do
  let(:repository_root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:documentation) { repository_root.join("docs/deployment.md").read }
  let(:workflow) { repository_root.join(".github/workflows/deploy.yml").read }
  let(:automation) { repository_root.join("lib/atlas/deployment_automation.rb").read }
  let(:launcher) { repository_root.join("bin/deployment-automation").read }

  it "documents the trusted main/prod workflow contract and both host paths" do
    expect(workflow).to include("- main", "- prod")
    expect(workflow).to include("ATLAS_PRODUCTION_ROOT: /srv/apps/ATLAS")
    expect(workflow).to include("ATLAS_STAGING_ROOT: /srv/apps/ATLAS-staging")
    expect(automation).to include('MAIN_REF = "refs/heads/main"')
    expect(automation).to include('PRODUCTION_REF = "refs/tags/prod"')
    expect(launcher).to include('require_relative "../lib/atlas/deployment_automation"')

    expect(documentation).to include(
      "`refs/heads/main`",
      "`refs/tags/prod`",
      "`/srv/apps/ATLAS`",
      "`/srv/apps/ATLAS-staging`",
      "`atlas.home.arpa`",
      "`atlas-staging.home.arpa`"
    )
    expect(documentation).to include(
      "A deleted `prod`, `main`, or `staging` ref may still enter the",
      "the automation returns `:ignored` before it mutates the deployment"
    )
  end

  it "states staging tracking, intentional pinning, CAS protection, and safe retry behavior" do
    expect(documentation).to include("`refs/tags/staging`")
    expect(documentation).to match(/tracking staging.*main|main.*tracking staging/i)
    expect(documentation).to match(/intentionally pinned staging|staging.*intentionally pinned/i)
    expect(documentation).to match(/compare-and-swap/i)
    expect(documentation).to include("--force-with-lease")
    expect(documentation).to match(/already advanced.*safe retry|safe retry.*already advanced/i)
  end

  it "documents staging post-tag deployment failure recovery and operator evidence" do
    expect(documentation).to include("Staging tag advancement happens before deployment")
    expect(documentation).to match(/`refs\/tags\/staging` may already point at the new\s+`main` revision\s+after a deployment failure/)
    expect(documentation).to match(/Rerun the failed workflow\s+for the same `main` revision/i)
    expect(documentation).to match(/Do not move the staging tag again\s+when it already\s+names that revision/)
    expect(documentation).to include("`GITHUB_BEFORE` and `GITHUB_SHA`", "the workflow run URL", "the compare-and-swap result")
    expect(documentation).to match(/the\s+direct and peeled `refs\/tags\/staging` values/)
    expect(documentation).to match(/the deployment checkout `git rev-parse HEAD` result/)
    expect(documentation).to match(/the `bin\/verify-deployment`\s+output/)
    expect(documentation).to include(
      "git ls-remote origin refs/tags/staging refs/tags/staging^{}",
      'git -C "$ATLAS_STAGING_ROOT" rev-parse HEAD',
      "gh run view <workflow-run-id> --json conclusion,headSha,url",
      "gh run rerun <workflow-run-id> --failed"
    )
  end

  it "documents authorized operator staging-tag advancement and recovery" do
    expect(documentation).to include("`bin/bump_staging_tag`", "HEAD:refs/tags/staging", "--force-with-lease")
    expect(documentation).to match(/authorized operators?/i)
    expect(documentation).to match(/committed `HEAD`/i)
    expect(documentation).to match(/direct and peeled `refs\/tags\/staging`/i)
    expect(documentation).to match(/inspect.*retry|retry.*inspect/i)
    expect(documentation).to match(/tag-event deployment.*main-driven tag advancement|main-driven tag advancement.*tag-event deployment/i)
    expect(documentation).to match(/stale.*missing.*annotated.*racing refs/im)
    expect(documentation).to match(/racing ref.*refused.*fails the workflow/im)
    expect(documentation).to match(/deleted\s+event.*ignored before.*remote ref query/im)
  end

  it "documents the administrator-owned external staging tag ruleset" do
    expect(documentation).to match(/external `staging` GitHub tag ruleset/i)
    expect(documentation).to match(/creation.*updates.*deletions/im)
    expect(documentation).to match(/approved users\/teams|approved users or teams/i)
    expect(documentation).to match(/GitHub Actions app/i)
    expect(documentation).to match(/administrator-owned/i)
  end

  it "makes revert-commit plus prod-tag-forward recovery authoritative" do
    expect(documentation).to match(/authoritative.*revert.*commit.*prod.*tag|revert.*commit.*prod.*tag.*authoritative/im)
    expect(documentation).to include(
      "git revert <faulty-commit>",
      "git push origin HEAD:main",
      "git ls-remote origin refs/tags/prod refs/tags/prod^{}",
      "git push --force-with-lease=refs/tags/prod:<current-prod-ref> origin <revert-commit>:refs/tags/prod",
      "bin/verify-deployment"
    )
    expect(documentation).to match(/`prod` tag.*forward|forward.*`prod` tag/im)
    expect(documentation).to match(/do not use.*bin\/deploy rollback.*primary|bin\/deploy rollback.*not.*primary/i)
    expect(documentation).to match(/After the workflow reports completion.*deployment host/im)
  end

  it "assigns homelab-manual issues #6, #7, and #8 in dependency order" do
    ownership_heading = documentation.match(/^## .*homelab-manual.*$/i)
    expect(ownership_heading).not_to be_nil
    ownership = ownership_heading ? documentation[ownership_heading.begin(0)..] : ""

    expect(ownership).to include("homelab-manual #6", "homelab-manual #7", "homelab-manual #8")
    expect(ownership).to match(/#6.*owner.*#7.*owner.*#8.*owner/im)
    expect(ownership).to match(/#6.*before.*#7.*before.*#8/im)
    expect(ownership).to match(/#7.*depends on.*#6/im)
    expect(ownership).to match(/#8.*depends on.*#7/im)
  end

  it "lists the repository and host verification commands" do
    [
      "docker compose config --quiet",
      "bin/verify-deployment",
      "docker compose ps",
      "docker compose port atlas 80",
      "git diff --check"
    ].each do |command|
      expect(documentation).to include(command)
    end
  end

  it "documents that automated updates use the deployment workflow as the verifier" do
    expect(documentation).to match(/`bin\/deploy update`, which performs the deployment readiness and\s+verification checks/)
    expect(documentation).to match(/The automation\s+does not run `bin\/verify-deployment` a second time/)
  end

  it "keeps examples free of secrets, private keys, and literal network addresses" do
    expect(documentation).not_to match(/-----BEGIN [^-]*PRIVATE KEY-----/)
    expect(documentation).not_to match(/(?:RAILS_MASTER_KEY\s*=\s*(?!FILE=)|(?:password|token|api[_-]?key)\s*[:=]\s*\S+)/i)
    expect(documentation).not_to match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/)
  end
end
