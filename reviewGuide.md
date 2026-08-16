# Review Guide
 
This is a guide on what needs reviewing in the code. As the codebase is mostly AI-generated, a developer needs to read over it and make sure everything makes sense and is cohesive.
 
1. **Documentation** - All documentation comments must use `///` on each line
    - Top of file
        - What part of the app the code is for
        - What structures are in the file
    - Comments in the file - The AI has written verbose comments
        - Consider the necessity of generated comments. Simplify if needed
        - Comment all non-obvious code as concisely as possible

2. **Design**
    - Architecture
        - **Consistency!!!** - No reinventing the wheel
        - No duplicate code - If two features are almost the same, use the same code (e.g. scrollable card view)
        - Simplicity is often key - both for readability and performance
    - Code style
        - All variables and functions use `lowerCamelCase`
        - Classes and structs use `UpperCamelCase`
        - **Consistency!!!**
        - Functions should not be unnecessarily long and complicated

3. **Bugs or weird stuff**
    - If something looks wrong or inefficient, rewrite it or get an AI to do so.
 
4. **Correctness & safety**
    - No force unwraps (`!`) or force-try (`try!`) without a clear comment explaining why it's safe
    - Check for retain cycles - `[weak self]` in closures that capture `self` and outlive the current scope

    ```swift
    class DataLoader {
        var onComplete: (() -> Void)?

        func load() {
            networkClient.fetch {   // memory leak
                self.onComplete?()   
            }
        }
        func load() {
            networkClient.fetch { [weak self] in    // fix
                self?.onComplete?()     
            }
        }
    }
    ```

    - Verify `@MainActor` / actor isolation is correct on anything touching UI or shared state (relevant given the concurrency migration work)
    - Check error handling isn't silently swallowed (empty `catch {}` blocks)

5. **SwiftUI-specific**
    - Views should be decomposed - flag any body that's grown too large or deeply nested
    - State ownership is correct
        - `@State` - variable that should not reset when view rerenders
        - `@StateObject` - class that should not reset when view rerenders
        - `@ObservedObject` - given to the view (argument)
        - `@Environment` - system provided values
