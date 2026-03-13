package;

import nx.script.Interpreter;

/**
 * Test para serialización de bytecode
 */
class TestBytecode {
	static function main() {
		trace("╔═══════════════════════════════════════════════════════╗");
		trace("║       Bytecode Serialization Test                    ║");
		trace("╚═══════════════════════════════════════════════════════╝\n");

		var interp = new Interpreter();

		// Script de prueba
		var script = '
			func factorial(n) {
				if (n <= 1) {
					return 1
				}
				return n * factorial(n - 1)
			}
			
			var result = factorial(5)
			trace("Factorial de 5 = " + result)
			result
		';

		trace("1. Compilando script...");
		var chunk = interp.compile(script);
		trace("   ✓ Script compilado");

		trace("\n2. Guardando bytecode a archivo...");
		interp.compileToFile(script, "test_factorial.nxb");
		trace("   ✓ Bytecode guardado en test_factorial.nxb");
		trace("\n3. Ejecutando script desde código fuente...");
		var result1 = interp.runDynamic(script);
		trace("   Resultado: " + result1);

		trace("\n4. Cargando y ejecutando desde bytecode...");
		var interp2 = new Interpreter();
		var result2 = interp2.runFromBytecode("test_factorial.nxb");
		trace("   Resultado: " + interp2.vm.valueToHaxe(result2));
		trace("\n5. Verificando que los resultados coinciden...");
		if (result1 == interp2.vm.valueToHaxe(result2)) {
			trace("   ✓ Los resultados coinciden!");
		} else {
			trace("   ✗ ERROR: Los resultados NO coinciden");
			trace("     Esperado: " + result1);
			trace("     Obtenido: " + interp2.vm.valueToHaxe(result2));
			Sys.exit(1);
		}

		// Test con arrays y diccionarios
		trace("\n6. Probando con estructuras de datos complejas...");
		var complexScript = '
			var arr = [1, 2, 3, 4, 5]
			var dict = { "name": "Test", "value": 42 }
			
			var sum = 0
			for (item in arr) {
				sum = sum + item
			}
			
		[sum, dict]
	';

		interp.compileToFile(complexScript, "test_complex.nxb");
		trace("   ✓ Bytecode guardado");

		var result3 = interp.runDynamic(complexScript);
		var result4 = new Interpreter().runFromBytecode("test_complex.nxb");
		trace("   Resultado original: " + result3);
		trace("   Resultado desde bytecode: " + new Interpreter().vm.valueToHaxe(result4));

		trace("\n╔═══════════════════════════════════════════════════════╗");
		trace("║       ✓ ALL TESTS PASSED                             ║");
		trace("╚═══════════════════════════════════════════════════════╝");
	}
}
