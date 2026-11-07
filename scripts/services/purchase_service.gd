extends Node
## In-app purchases behind one interface. Mock: every purchase succeeds after
## a short delay. A store SDK replaces `_pay` and `restore` and nothing else.

signal purchase_finished(product_id: String, ok: bool)

var fail_next := false

func buy(product_id: String, done: Callable) -> void:
	get_tree().create_timer(0.6).timeout.connect(func():
		var ok := not fail_next
		fail_next = false
		purchase_finished.emit(product_id, ok)
		done.call(ok))

## Restore previously bought one-time products (mock: nothing to restore).
func restore(done: Callable) -> void:
	get_tree().create_timer(0.4).timeout.connect(func(): done.call([]))
