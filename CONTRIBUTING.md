# Contributing

Thanks for your interest in this project! Every contribution is welcome: bug
reports, new features, documentation, performance work, a typo in a README, or
anything else. If you are here, you are already helping 💚.

This guide explains the flow, from "I have an idea" to "my pull request is
merged". Please read it before you open an issue or write code: it will save
time for you and for the maintainer (me 🙏).

None of the rules below exist to make your life harder. They exist so that your
work does not end up in a drawer.

- [Contributing](#contributing)
  - [1. Start from the roadmap](#1-start-from-the-roadmap)
  - [2. Search before you open an issue](#2-search-before-you-open-an-issue)
  - [3. Open an issue (not a pull request)](#3-open-an-issue-not-a-pull-request)
  - [4. Everyone gets the credit](#4-everyone-gets-the-credit)
  - [5. Tell us if you want to work on it](#5-tell-us-if-you-want-to-work-on-it)
  - [6. How to read the answers on an issue](#6-how-to-read-the-answers-on-an-issue)
  - [7. Open the pull request](#7-open-the-pull-request)
    - [What the CI checks](#what-the-ci-checks)
  - [8. AI-assisted contributions](#8-ai-assisted-contributions)

## 1. Start from the roadmap

The [roadmap][roadmap] is the best place to start. It is a GitHub project board
where all the planned work is collected and ordered, so you can see what is
already done, what is in progress, and what is only an idea.

Looking at it first helps you understand where your contribution fits, and
avoids work on something that is already being done (possibly by me 👷, right
now, in another branch).

## 2. Search before you open an issue

Before creating a new issue, please look at the
[existing issues][issues] (open **and** closed) and search for your topic.

Many problems are already reported, and duplicates split the discussion in two
places, so half of the context is always in the other one. If you find an issue
that matches yours, join it instead of opening a new one: a good comment on an
open thread is worth as much as a new issue, sometimes more 💬.

And if you are not sure whether it is the same problem? Open the issue anyway.
Closing a duplicate takes one click, a lost bug report takes months.

## 3. Open an issue (not a pull request)

**Every change starts with an issue.** Please do not send a pull request
directly: we first want to discuss the problem and agree on a solution. Talking
first is the fastest path to a merge — nobody enjoys writing "thanks, but..."
under a pull request that already cost you a weekend 😅.

Issues are created from [templates][new-issue] with specific fields (one
template per package, plus bug and enhancement variants). Choose the template
that fits your case and fill every field as well as you can: the more precise
the description, the faster the answer. If a field really does not apply to you,
write it — an honest "I don't know" is a perfectly good answer.

And if you do not plan to write the fix yourself, you are still very welcome:
code fragments, ideas, or a rough implementation sketch in the details of the
issue are a real contribution.

## 4. Everyone gets the credit

Writing the code yourself is optional: a well-described issue is already a
contribution, and someone else (often me) can take it from there 🤝.

Either way your name goes in the CHANGELOG entry, next to the issue link:
`(thx to @name)` for the report, `(PR by @name)` for the code.

## 5. Tell us if you want to work on it

If you want to solve the problem yourself and propose a pull request, write it
clearly in the issue, and add two more pieces of information:

- **when** you think you can start the work;
- **how long** it would take you, roughly (a rough estimate is fine).

This is not a commitment and nobody will check the calendar ⏰. The goal is only
to understand the timing: if a change is needed for other work, the maintainer
(still me 🙋) has to know whether to wait for you or to move on.

## 6. How to read the answers on an issue

Between your message and a written answer there can be some time (this project
is maintained in the free time of one person ☕). To make the state visible,
issues and comments are marked with an emoji:

| State           | Meaning                                           |
|-----------------|---------------------------------------------------|
| no reaction     | the message has not been read yet                 |
| 👀              | the message was received and is being analyzed    |
| a written reply | the analysis is done, the discussion can continue |

So if you see the 👀 reaction, your issue is not forgotten: it is simply still
under review. And if a week passes with no sign of life, a friendly ping in the
thread is absolutely allowed 🔔.

## 7. Open the pull request

Since every pull request starts from an issue, branches are named after it:
`issues/<issue_num>`, or `hotfix/<issue_num>` when the change is a fix. One
issue, one branch, one pull request.

When the solution is agreed in the issue, you can open the pull request:

- **Link the issue** in the description with `#issue_num`, so the discussion and
  the code stay connected.
- **Follow the workspace conventions.** The [README][readme] explains the
  workspace, the organization of the repository, and the melos setup. Each
  package also has its own README with more detail.
- **Check your work before pushing:**

  ```bash
  melos run format
  melos run analyze
  melos run test
  melos run test_flutter
  ```

- If your change is user-facing, add an entry to the CHANGELOG of the package
  you touched. The changelogs are written prose, not a list of commits.

Do not worry about getting everything right on the first push: review here is a
conversation, not an exam 🎓. A draft pull request with an open question in the
description is perfectly fine.

### What the CI checks

On every pull request, each touched package is checked with:

- **format** — `dart format` with 80 characters per line;
- **analyze** — `dart analyze --fatal-infos --fatal-warnings`; the lints are
  strict and include `public_member_api_docs`, so an undocumented public API
  fails the build;
- **tests** — the Dart tests, the web ones (`dart test -p chrome`) and, for the
  Flutter packages, `flutter test`;
- **coverage** — a minimum threshold per package (from 70% to 90%).

The coverage gate is the reason why **new behaviour needs new tests**: untested
code lowers the percentage, the threshold is not reached and the pull request
stays red 🔴. The opposite is also true, though — tests that only repeat what is
already covered add noise, not value.

`melos run format`, `melos run analyze` and the test scripts run the same
checks locally, so the surprises stay on your machine.

## 8. AI-assisted contributions

Using AI to work on this project is fine, and you do not have to hide it.

The only rule is that **at least one human quality review must happen before the
pull request is sent**. Read the generated code, understand it, test it, and be
able to explain why it works — because in review you will be asked, kindly but
seriously 🤖➡️🧑‍💻. 

### The project can be *supported* by AI, but not *driven* by it.

---

That's all. If something in this guide is unclear, that is a bug too: open an
issue about it and we will fix it together.

[roadmap]: https://github.com/users/MattiaPispisa/projects/1
[issues]: https://github.com/MattiaPispisa/crdt/issues
[new-issue]: https://github.com/MattiaPispisa/crdt/issues/new/choose
[readme]: ./README.md
