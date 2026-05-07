---
title: "Go private packages"
date: 2020-10-04
description: "How to deal with private packages in Go."
---

**TL;DR**
_git submodules_

## What's the matter?

Imagine a situation when you're following best practices, splitting your code into different parts, and ... facing an issue to collect them.
Unfortunately, Go does not support private packages well.

## So, how?

I'll describe the situation I faced. Private go mod packages, located in the GitLab subgroup (let's say `gitlab.com/org/department/repo1.git` just for example)

First, Go doesn't actually support GitLab subgroups. To bypass that issue, we need to set GOPRIVATE env variable and add .git in the end:

```bash
$ GOPRIVATE="gitlab.com/org/department" go get gitlab.com/org/department/repo1.git
```

Second barrier is access to that repo. SSH key must be added to the platform, I didn't find a way to fetch with https.

Pros:
- Native experience (go get, which handles `go.mod` changes itself)

Cons:
- SSH key must be set
- go.mod package name must fully correspond that naming (with `.git` in the end)

## Problem is solved ... or not?

The first problem surfaced just half an hour later. It's a CI/CD, or just building step.
As we understood from previous "summary", SSH key must be added. We are using Docker to build our project, and passing SSH key to the Dockerfile build actually is a security problem.

## Alternative way

I found a solution in **_git submodules_** and **_replace_** feature for the `go.mod`.
Just add needed repo as a project submodule with `git submodule add` and add naming replacement in the `go.mod`.
For example:

Adding submodule
```
$ git submodule add ../repo1
```

Pulling newly added repo
```
$ git submodule update --init
```

Adding `go.mod` replacement
```
replace gitlab.com/org/department/repo1.git => ./repo1
```

And that's all! Handling package as a submodule is much easier than go package.

P.S. Don't forget to add submodules pulling in your CI! In case of GitLab it's `GIT_SUBMODULE_STRATEGY: recursive` variable.

Thank you for reading!
