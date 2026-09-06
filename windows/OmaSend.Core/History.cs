namespace OmaSend.Core;

public sealed class History
{
    private readonly object gate = new();
    private readonly List<Message> items = [];
    // Separate bounded replay cache survives a history clear during this process.
    private readonly HashSet<string> seen = [];
    private readonly Queue<string> order = [];
    public Message[] Snapshot { get { lock (gate) return [.. items]; } }
    public bool Remember(string id)
    {
        lock (gate)
        {
            if (!seen.Add(id)) return false;
            order.Enqueue(id);
            while (order.Count > 4096) seen.Remove(order.Dequeue());
            return true;
        }
    }
    public bool Add(Message message)
    {
        lock (gate)
        {
            if (!Remember(message.Id)) return false;
            items.Insert(0, message);
            while (items.Count > 50 || items.Sum(m => (long)(m.Text?.Length ?? 0) * 2 + (m.Data?.Length ?? 0) * 2) > 50 * 1024 * 1024)
                items.RemoveAt(items.Count - 1);
            return true;
        }
    }
    public void Clear() { lock (gate) items.Clear(); }
}
