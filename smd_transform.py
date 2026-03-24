#!/usr/bin/env python3
"""
SMD 模型变换工具（平移、缩放）
用法:
    # 平移（手动偏移）
    python smd_transform.py input.smd output.smd --translate 0 0 -6.4

    # 自动中心化（Z 轴中心移至原点）
    python smd_transform.py input.smd output.smd --center

    # 缩放（指定缩放因子）
    python smd_transform.py input.smd output.smd --scale 1.25

    # 缩放至目标边长（假设立方体）
    python smd_transform.py input.smd output.smd --target_size 16

    # 组合操作（先缩放再平移）
    python smd_transform.py input.smd output.smd --scale 1.25 --center
"""

import sys
import re
import argparse
from dataclasses import dataclass, field
from typing import List, Tuple, Optional


# ------------------------------------------------------------
# 数据结构
# ------------------------------------------------------------
@dataclass
class Vertex:
    """单个顶点数据"""

    bone_idx: int
    x: float
    y: float
    z: float
    nx: float
    ny: float
    nz: float
    u: float
    v: float
    links: int = 1
    bone_indices: List[int] = field(default_factory=lambda: [0])
    weights: List[float] = field(default_factory=lambda: [1.0])

    @classmethod
    def from_line(cls, line: str) -> "Vertex":
        parts = line.strip().split()
        if len(parts) < 12:
            raise ValueError(f"顶点行格式错误: {line}")
        bone_idx = int(parts[0])
        x = float(parts[1])
        y = float(parts[2])
        z = float(parts[3])
        nx = float(parts[4])
        ny = float(parts[5])
        nz = float(parts[6])
        u = float(parts[7])
        v = float(parts[8])
        links = int(parts[9])
        bone_indices = []
        weights = []
        idx = 10
        for i in range(links):
            if idx + 1 >= len(parts):
                raise ValueError(f"顶点行缺少权重数据: {line}")
            bone_indices.append(int(parts[idx]))
            weights.append(float(parts[idx + 1]))
            idx += 2
        return cls(bone_idx, x, y, z, nx, ny, nz, u, v, links, bone_indices, weights)

    def to_line(self) -> str:
        parts = [
            str(self.bone_idx),
            f"{self.x:.6f}",
            f"{self.y:.6f}",
            f"{self.z:.6f}",
            f"{self.nx:.6f}",
            f"{self.ny:.6f}",
            f"{self.nz:.6f}",
            f"{self.u:.6f}",
            f"{self.v:.6f}",
            str(self.links),
        ]
        for bi, w in zip(self.bone_indices, self.weights):
            parts.append(str(bi))
            parts.append(f"{w:.6f}")
        return "  " + " ".join(parts) + "\n"

    def translate(self, dx: float = 0.0, dy: float = 0.0, dz: float = 0.0):
        self.x += dx
        self.y += dy
        self.z += dz

    def scale(self, sx: float = 1.0, sy: float = 1.0, sz: float = 1.0):
        """缩放顶点坐标（相对于原点）"""
        self.x *= sx
        self.y *= sy
        self.z *= sz


@dataclass
class Triangle:
    material: str
    vertices: List[Vertex]  # 三个顶点

    @classmethod
    def from_block(cls, material: str, lines: List[str]) -> "Triangle":
        if len(lines) != 3:
            raise ValueError(f"三角形需要三行顶点数据，得到 {len(lines)} 行")
        verts = [Vertex.from_line(line) for line in lines]
        return cls(material, verts)

    def to_block(self) -> List[str]:
        lines = [self.material + "\n"]
        for v in self.vertices:
            lines.append(v.to_line())
        return lines

    def translate(self, dx: float = 0.0, dy: float = 0.0, dz: float = 0.0):
        for v in self.vertices:
            v.translate(dx, dy, dz)

    def scale(self, sx: float = 1.0, sy: float = 1.0, sz: float = 1.0):
        for v in self.vertices:
            v.scale(sx, sy, sz)


# ------------------------------------------------------------
# SMD 文档
# ------------------------------------------------------------
class SMDDocument:
    def __init__(self):
        self.header_lines = []
        self.triangles: List[Triangle] = []
        self.footer_lines = []

    @classmethod
    def from_file(cls, path: str) -> "SMDDocument":
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        doc = cls()
        state = "header"
        current_material = None
        current_vert_lines = []
        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()

            if state == "header":
                if stripped == "triangles":
                    doc.header_lines.append(line)
                    state = "triangles"
                    i += 1
                    continue
                else:
                    doc.header_lines.append(line)
                    i += 1
                    continue

            if state == "triangles":
                if stripped == "" or stripped == "end":
                    doc.footer_lines.append(line)
                    state = "footer"
                    i += 1
                    continue

                if not re.match(r"^\s*\d", line):
                    if current_material is not None and len(current_vert_lines) == 3:
                        doc.triangles.append(
                            Triangle.from_block(current_material, current_vert_lines)
                        )
                        current_vert_lines = []
                    current_material = stripped
                    i += 1
                    continue

                if current_material is None:
                    i += 1
                    continue
                current_vert_lines.append(line)
                if len(current_vert_lines) == 3:
                    doc.triangles.append(
                        Triangle.from_block(current_material, current_vert_lines)
                    )
                    current_vert_lines = []
                i += 1
                continue

            if state == "footer":
                doc.footer_lines.append(line)
                i += 1

        if current_material is not None and len(current_vert_lines) == 3:
            doc.triangles.append(
                Triangle.from_block(current_material, current_vert_lines)
            )

        return doc

    def write(self, path: str):
        with open(path, "w", encoding="utf-8") as f:
            for line in self.header_lines:
                f.write(line)
            for tri in self.triangles:
                for line in tri.to_block():
                    f.write(line)
            for line in self.footer_lines:
                f.write(line)

    def translate(self, dx: float = 0.0, dy: float = 0.0, dz: float = 0.0):
        for tri in self.triangles:
            tri.translate(dx, dy, dz)

    def scale(self, sx: float = 1.0, sy: float = 1.0, sz: float = 1.0):
        for tri in self.triangles:
            tri.scale(sx, sy, sz)

    def get_bounds(
        self,
    ) -> Tuple[Tuple[float, float, float], Tuple[float, float, float]]:
        """获取所有顶点的最小/最大坐标"""
        if not self.triangles:
            return ((0, 0, 0), (0, 0, 0))
        min_x = min_y = min_z = float("inf")
        max_x = max_y = max_z = float("-inf")
        for tri in self.triangles:
            for v in tri.vertices:
                min_x = min(min_x, v.x)
                min_y = min(min_y, v.y)
                min_z = min(min_z, v.z)
                max_x = max(max_x, v.x)
                max_y = max(max_y, v.y)
                max_z = max(max_z, v.z)
        return (min_x, min_y, min_z), (max_x, max_y, max_z)

    def compute_center(self) -> Tuple[float, float, float]:
        """计算模型几何中心（最小+最大）/2"""
        (min_x, min_y, min_z), (max_x, max_y, max_z) = self.get_bounds()
        return ((min_x + max_x) / 2, (min_y + max_y) / 2, (min_z + max_z) / 2)


# ------------------------------------------------------------
# 主程序
# ------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="变换 SMD 模型顶点（平移、缩放）")
    parser.add_argument("input", help="输入 SMD 文件")
    parser.add_argument("output", help="输出 SMD 文件")

    # 平移选项
    trans_group = parser.add_mutually_exclusive_group()
    trans_group.add_argument(
        "--translate",
        nargs=3,
        type=float,
        metavar=("DX", "DY", "DZ"),
        help="平移偏移量",
    )
    trans_group.add_argument(
        "--center", action="store_true", help="自动将模型几何中心移至原点"
    )

    # 缩放选项
    scale_group = parser.add_mutually_exclusive_group()
    scale_group.add_argument("--scale", type=float, help="均匀缩放因子")
    scale_group.add_argument(
        "--target_size", type=float, help="目标边长（假设模型为立方体）"
    )

    args = parser.parse_args()

    # 加载文档
    doc = SMDDocument.from_file(args.input)

    # 缩放处理
    if args.target_size:
        # 获取当前 Z 范围长度（假设模型为立方体，但实际可能不对称，这里取 Z 范围长度）
        (_, _, min_z), (_, _, max_z) = doc.get_bounds()
        current_size = max_z - min_z
        if current_size == 0:
            raise ValueError("模型 Z 方向尺寸为零，无法计算缩放因子")
        scale_factor = args.target_size / current_size
        print(
            f"当前 Z 范围长度: {current_size:.6f}, 目标边长: {args.target_size}, 缩放因子: {scale_factor:.6f}"
        )
        doc.scale(scale_factor, scale_factor, scale_factor)
    elif args.scale:
        print(f"应用均匀缩放因子: {args.scale:.6f}")
        doc.scale(args.scale, args.scale, args.scale)

    # 平移处理
    if args.translate:
        dx, dy, dz = args.translate
        print(f"平移: ({dx}, {dy}, {dz})")
        doc.translate(dx, dy, dz)
    elif args.center:
        cx, cy, cz = doc.compute_center()
        print(f"几何中心: ({cx:.6f}, {cy:.6f}, {cz:.6f})，移至原点")
        doc.translate(-cx, -cy, -cz)

    # 写入输出文件
    doc.write(args.output)
    print(f"已保存至 {args.output}")


if __name__ == "__main__":
    main()
