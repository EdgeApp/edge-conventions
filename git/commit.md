# [<](README.md) &nbsp; Commit rules

- [Subject Line](#subject-line)
  - [Use the imperative mood in the subject line](#use-the-imperative-mood-in-the-subject-line)
  - [Limit the subject line to 50 characters](#limit-the-subject-line-to-50-characters)
  - [Capitalize the subject line](#capitalize-the-subject-line)
  - [Do not end the subject line with a period](#do-not-end-the-subject-line-with-a-period)
- [Body](#body)
  - [Use the body to explain what and why vs. how](#use-the-body-to-explain-what-and-why-vs-how)
  - [Separate body from subject with a blank line](#separate-body-from-subject-with-a-blank-line)
  - [Wrap the body at 72 characters](#wrap-the-body-at-72-characters)

&nbsp;

## Subject Line

---

### Use the imperative mood in the subject line

```bash
# incorrect
git commit -m "Fixed bug with Y"
git commit -m "Changing behavior of X"
git commit -m "More fixes for broken stuff"
git commit -m "Sweet new API methods"
```

```bash
# correct
git commit -m "Refactor subsystem X for readability"
git commit -m "Update getting started documentation"
git commit -m "Remove deprecated methods"
git commit -m "Release version 1.0.0"
```

### Limit the subject line to 50 characters

```bash
# incorrect (> 50 chars)
git commit -m "Add NEW_WALLET action to global action file and add NEW_WALLET action creator"
```

```bash
# correct
git commit -m "Add NEW_WALLET action and action creator"
```

### Capitalize the subject line

```bash
# incorrect
git commit -m "accelerate to 88 miles per hours"
```

```bash
# correct
git commit -m "Accelerate to 88 miles per hour"
```

### Do not end the subject line with a period

```bash
# incorrect
git commit -m "Open the pod bay doors."
```

```bash
# correct
git commit -m "Open the pod bay doors"
```

&nbsp;

## Body

---

### Use the body to explain what and why vs. how

```bash
# incorrect
git commit -m "Decrease time to send transaction

This pull request moves the http request to after signing and sending
transactions.
"
```

```bash
# correct
git commit -m "Decrease time to send transaction

The core makes an http request prior to sending each transaction. It
then waits for the return of this request before sending the
transaction. This request took several seconds and is not required to
to complete before sending the transaction.

Moving the request until after the transaction is sent decreases
the time the use spends waiting to send a transaction.
"
```

### Separate body from subject with a blank line

```bash
# incorrect

git commit -m "Derezz the master control program
MCP turned out to be evil and had become intent on world domination.
This commit throws Tron's disc into MCP (causing its deresolution)
and turns it back into a chess game."
```

```bash
# correct

git commit -m "Derezz the master control program

MCP turned out to be evil and had become intent on world domination.
This commit throws Tron's disc into MCP (causing its deresolution)
and turns it back into a chess game."
```

### Wrap the body at 72 characters

```bash
# incorrect (does not wrap at 72 chars)
git commit -m "Simplify serialize.h's exception handling

Remove the 'state' and 'exceptmask' from serialize.h's stream implementations, as well as related methods.

As exceptmask always included 'failbit', and setstate was always called with bits = failbit, all it did was immediately raise an exception. Get rid of those variables, and replace the setstate with direct exception throwing (which also removes some dead code)."
```

```bash
# correct
git commit -m "Simplify serialize.h's exception handling

Remove the 'state' and 'exceptmask' from serialize.h's stream
implementations, as well as related methods.

As exceptmask always included 'failbit', and setstate was always
called with bits = failbit, all it did was immediately raise an
exception. Get rid of those variables, and replace the setstate
with direct exception throwing (which also removes some dead
code)."
```

source: [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/#seven-rules)

[Back to the top](#--commit-rules)
