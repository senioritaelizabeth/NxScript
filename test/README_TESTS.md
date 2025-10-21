# Nz-Dialogue Test Suite

## Running the Interactive Test Menu

To run the test suite with the interactive menu:

```bash
haxe test.hxml
```

### Navigation

- **↑ ↓ Arrow Keys**: Navigate through menu options
- **Enter**: Select the highlighted option
- **Q** or **ESC**: Go back to previous menu / Exit

### Menu Structure

```
Main Menu:
  > Test Dialogues
    Test Cinematic (Coming soon)
    Test Scripting Bytecode (Coming soon)
    Exit

Test Dialogues Submenu:
  > All Tests         - Run complete test suite (42 tests)
    Variables         - Test variable assignments
    Functions         - Test function definitions
    Function Calls    - Test function invocations
    Dialogs           - Test dialog lines
    @Commands         - Test @command syntax
    Comparison Operators - Test >, <, ==, !=, >=, <=
    Logical Operators - Test &&, ||, !, and, or, not
    Boolean Variables - Test true/false values
    Complex Conditions - Test nested conditions with parentheses
    Control Flow      - Test if/elseif/else/switch
```

## Test Files

- **test/all_tests.dia** - Comprehensive dialogue test file with all features
- **test/TestMain.hx** - Interactive test menu system
- **test/AllTests.hx** - Legacy test runner (deprecated)

## Features Tested

✅ Variable assignments and arithmetic operations
✅ Function definitions and calls
✅ Dialog lines and @commands
✅ Comparison operators (>, <, ==, !=, >=, <=)
✅ Logical operators (&&, ||, !)
✅ Word operator synonyms (and, or, not)
✅ Boolean variables (true/false)
✅ Complex nested conditions
✅ Control flow (if/elseif/else/switch)

## Note

The interactive menu uses PowerShell's `RawUI.ReadKey()` on Windows for proper arrow key detection.
If you experience issues, make sure you're running in a proper terminal (not VS Code's output panel).

You can also run tests directly:

```bash
haxe -cp test -cp src --run AllTests  # Run all tests without menu
```
